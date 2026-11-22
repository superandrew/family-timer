import XCTest
@testable import FamilyTimerCore

final class PolicyTests: XCTestCase {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Rome")!
        return c
    }()

    let config = Config(childUser: "a", weekdayLimit: 3600, weekendLimit: 7200,
                        extensionTime: 1800, graceTime: 300, approvalTimeout: 600,
                        telegramBotToken: "token", telegramChatID: "-100")

    /// Monday 2026-11-23 in Rome.
    func at(_ h: Int, _ m: Int, _ s: Int = 0, day: Int = 23) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day,
                                           hour: h, minute: m, second: s))!
    }

    func reduce(_ state: PolicyState, _ event: PolicyEvent, _ now: Date,
                config: Config? = nil) -> (PolicyState, [PolicyAction]) {
        Policy.reduce(state, event, now: now, config: config ?? self.config, calendar: calendar)
    }

    func state(used: Int = 0, extra: Int = 0, phase: Phase = .open) -> PolicyState {
        PolicyState(ledger: DayLedger(day: "2026-11-23", used: used, extra: extra), phase: phase)
    }

    /// Budget used up at 10:00, grace until 10:05.
    func inGrace() -> PolicyState {
        let (s, _) = reduce(state(used: 3600 - 15), .tick(seconds: 15, active: true), at(10, 0))
        return s
    }

    /// Request r1 sent at 10:01 (deadline 10:11), grace until 10:05.
    func inPending() -> PolicyState {
        let (s, _) = reduce(inGrace(), .askForTime(requestID: "r1"), at(10, 1))
        return s
    }

    /// Request r1 unanswered, locked at the end of grace, 10:05.
    func lockedWithRequest() -> PolicyState {
        let (s, _) = reduce(inPending(), .tick(seconds: 15, active: true), at(10, 5))
        return s
    }

    /// Locked at 10:05 at the end of grace, no request.
    func lockedNoRequest() -> PolicyState {
        let (s, _) = reduce(inGrace(), .tick(seconds: 15, active: true), at(10, 5))
        return s
    }

    // MARK: open

    func testActiveTickCounts() {
        let (s, actions) = reduce(state(used: 100), .tick(seconds: 15, active: true), at(9, 0))
        XCTAssertEqual(s.ledger.used, 115)
        XCTAssertEqual(s.phase, .open)
        XCTAssertEqual(actions, [])
    }

    func testIdleTickDoesNotCount() {
        let (s, actions) = reduce(state(used: 100), .tick(seconds: 15, active: false), at(9, 0))
        XCTAssertEqual(s.ledger.used, 100)
        XCTAssertEqual(actions, [])
    }

    func testBudgetOverEntersGrace() {
        let (s, actions) = reduce(state(used: 3600 - 15), .tick(seconds: 15, active: true), at(10, 0))
        XCTAssertEqual(s.ledger.used, 3600)
        XCTAssertEqual(s.phase, .grace)
        XCTAssertEqual(s.graceUntil, at(10, 5))
        XCTAssertEqual(actions, [.showExpiredDialog])
    }

    func testWeekendBudget() {
        let saturday = PolicyState(ledger: DayLedger(day: "2026-11-21", used: 3600))
        let (s, actions) = reduce(saturday, .tick(seconds: 15, active: true), at(10, 0, day: 21))
        XCTAssertEqual(s.phase, .open)
        XCTAssertEqual(actions, [])
        XCTAssertEqual(Policy.remaining(s, now: at(10, 0, day: 21), config: config,
                                        calendar: calendar), 7200 - 3615)
    }

    // MARK: grace

    func testGraceIsNotCharged() {
        let (s, _) = reduce(inGrace(), .tick(seconds: 15, active: true), at(10, 1))
        XCTAssertEqual(s.ledger.used, 3600)
        XCTAssertEqual(s.phase, .grace)
    }

    func testGraceEndLocks() {
        let (before, none) = reduce(inGrace(), .tick(seconds: 15, active: true), at(10, 4, 59))
        XCTAssertEqual(before.phase, .grace)
        XCTAssertEqual(none, [])
        let (s, actions) = reduce(inGrace(), .tick(seconds: 15, active: true), at(10, 5))
        XCTAssertEqual(s.phase, .locked)
        XCTAssertNil(s.graceUntil)
        XCTAssertEqual(s.lockSentAt, at(10, 5))
        XCTAssertEqual(actions, [.lock])
    }

    // MARK: asking

    func testAskInGraceSendsRequest() {
        let (s, actions) = reduce(inGrace(), .askForTime(requestID: "r1"), at(10, 1))
        XCTAssertEqual(s.phase, .pending)
        XCTAssertEqual(s.request, PendingRequest(id: "r1", seconds: 1800, deadline: at(10, 11)))
        XCTAssertEqual(s.graceUntil, at(10, 5))
        XCTAssertEqual(actions, [.sendTimeRequest(requestID: "r1", seconds: 1800)])
    }

    func testAskOutsideGraceIsIgnored() {
        let (open, a1) = reduce(state(), .askForTime(requestID: "r1"), at(9, 0))
        XCTAssertEqual(open, state())
        XCTAssertEqual(a1, [])
        let (pending, a2) = reduce(inPending(), .askForTime(requestID: "r2"), at(10, 2))
        XCTAssertEqual(pending, inPending())
        XCTAssertEqual(a2, [])
        let (locked, a3) = reduce(lockedWithRequest(), .askForTime(requestID: "r2"), at(10, 6))
        XCTAssertEqual(locked, lockedWithRequest())
        XCTAssertEqual(a3, [])
    }

    func testAskWithoutTelegramIsDenied() {
        var noTelegram = config
        noTelegram.telegramBotToken = ""
        let (s, actions) = reduce(inGrace(), .askForTime(requestID: "r1"), at(10, 1),
                                  config: noTelegram)
        XCTAssertEqual(s.phase, .grace)
        XCTAssertNil(s.request)
        XCTAssertEqual(actions, [.requestResult(requestID: "r1", approved: false)])
    }

    // MARK: answers

    func testApproveInPendingOpens() {
        let (s, actions) = reduce(inPending(), .answer(requestID: "r1", approved: true), at(10, 2))
        XCTAssertEqual(s.phase, .open)
        XCTAssertNil(s.request)
        XCTAssertNil(s.graceUntil)
        XCTAssertEqual(s.ledger.extra, 1800)
        XCTAssertEqual(Policy.remaining(s, now: at(10, 2), config: config, calendar: calendar), 1800)
        XCTAssertEqual(actions, [.requestResult(requestID: "r1", approved: true)])
    }

    func testDenyInPendingLocks() {
        let (s, actions) = reduce(inPending(), .answer(requestID: "r1", approved: false), at(10, 2))
        XCTAssertEqual(s.phase, .locked)
        XCTAssertNil(s.request)
        XCTAssertEqual(actions, [.requestResult(requestID: "r1", approved: false), .lock])
    }

    func testPendingLocksAtGraceEndAndKeepsRequest() {
        let s = lockedWithRequest()
        XCTAssertEqual(s.phase, .locked)
        XCTAssertEqual(s.request?.id, "r1")
    }

    func testPendingLocksAtApprovalTimeout() {
        var longGrace = config
        longGrace.graceTime = 900
        let (grace, _) = reduce(state(used: 3600 - 15), .tick(seconds: 15, active: true),
                                at(10, 0), config: longGrace)
        let (pending, _) = reduce(grace, .askForTime(requestID: "r1"), at(10, 0), config: longGrace)
        let (before, _) = reduce(pending, .tick(seconds: 15, active: true), at(10, 9, 59),
                                 config: longGrace)
        XCTAssertEqual(before.phase, .pending)
        let (s, actions) = reduce(pending, .tick(seconds: 15, active: true), at(10, 10),
                                  config: longGrace)
        XCTAssertEqual(s.phase, .locked)
        XCTAssertEqual(actions, [.lock])
    }

    func testLateApproveUnlocks() {
        let (s, actions) = reduce(lockedWithRequest(), .answer(requestID: "r1", approved: true),
                                  at(10, 20))
        XCTAssertEqual(s.phase, .open)
        XCTAssertEqual(s.ledger.extra, 1800)
        XCTAssertNil(s.lockSentAt)
        XCTAssertEqual(actions, [.requestResult(requestID: "r1", approved: true), .unlock])
    }

    func testLateDenyStaysLocked() {
        let (s, actions) = reduce(lockedWithRequest(), .answer(requestID: "r1", approved: false),
                                  at(10, 20))
        XCTAssertEqual(s.phase, .locked)
        XCTAssertNil(s.request)
        XCTAssertEqual(actions, [.requestResult(requestID: "r1", approved: false)])
    }

    func testUnknownOrRepeatedAnswerIsIgnored() {
        let (s1, a1) = reduce(inPending(), .answer(requestID: "other", approved: true), at(10, 2))
        XCTAssertEqual(s1, inPending())
        XCTAssertEqual(a1, [])
        let (approved, _) = reduce(inPending(), .answer(requestID: "r1", approved: true), at(10, 2))
        let (s2, a2) = reduce(approved, .answer(requestID: "r1", approved: true), at(10, 3))
        XCTAssertEqual(s2, approved)
        XCTAssertEqual(a2, [])
    }

    // MARK: commands

    func testStatusAndHelpChangeNothing() {
        for command in [Command.status, .help] {
            let (s, actions) = reduce(inPending(), .command(command), at(10, 2))
            XCTAssertEqual(s, inPending())
            XCTAssertEqual(actions, [])
        }
    }

    func testExtraWhileOpenAddsTime() {
        let (s, actions) = reduce(state(used: 100), .command(.extra(seconds: 600)), at(9, 0))
        XCTAssertEqual(s.ledger.extra, 600)
        XCTAssertEqual(s.phase, .open)
        XCTAssertEqual(actions, [])
    }

    func testExtraWhileLockedUnlocksAndCancelsRequest() {
        let (s, actions) = reduce(lockedWithRequest(), .command(.extra(seconds: 600)), at(10, 20))
        XCTAssertEqual(s.phase, .open)
        XCTAssertNil(s.request)
        XCTAssertEqual(s.ledger.extra, 600)
        XCTAssertEqual(actions, [.cancelRequest(requestID: "r1"), .unlock])
    }

    func testExtraWhilePendingOpens() {
        let (s, actions) = reduce(inPending(), .command(.extra(seconds: 600)), at(10, 2))
        XCTAssertEqual(s.phase, .open)
        XCTAssertNil(s.graceUntil)
        XCTAssertEqual(actions, [.cancelRequest(requestID: "r1")])
    }

    func testStudioPausesCountingThenGraceAtItsEnd() {
        let (studio, actions) = reduce(lockedWithRequest(), .command(.studio(seconds: 3600)),
                                       at(10, 20))
        XCTAssertEqual(studio.phase, .open)
        XCTAssertEqual(studio.ledger.studioUntil, at(11, 20))
        XCTAssertEqual(actions, [.cancelRequest(requestID: "r1"), .unlock])

        let (during, a1) = reduce(studio, .tick(seconds: 15, active: true), at(11, 0))
        XCTAssertEqual(during.ledger.used, 3600)
        XCTAssertEqual(during.phase, .open)
        XCTAssertEqual(a1, [])

        let (after, a2) = reduce(during, .tick(seconds: 15, active: true), at(11, 20))
        XCTAssertEqual(after.phase, .grace)
        XCTAssertEqual(after.graceUntil, at(11, 25))
        XCTAssertEqual(a2, [.showExpiredDialog])
    }

    func testParentLockHoldsUntilUnlock() {
        let (locked, a1) = reduce(state(used: 100), .command(.lock), at(9, 0))
        XCTAssertEqual(locked.phase, .locked)
        XCTAssertTrue(locked.ledger.lockedByParent)
        XCTAssertEqual(a1, [.lock])

        let (afterExtra, a2) = reduce(locked, .command(.extra(seconds: 600)), at(9, 1))
        XCTAssertEqual(afterExtra.phase, .locked)
        XCTAssertEqual(afterExtra.ledger.extra, 600)
        XCTAssertEqual(a2, [])

        let (afterStudio, a3) = reduce(locked, .command(.studio(seconds: 600)), at(9, 1))
        XCTAssertEqual(afterStudio.phase, .locked)
        XCTAssertEqual(a3, [])

        let (unlocked, a4) = reduce(locked, .command(.unlock), at(9, 2))
        XCTAssertEqual(unlocked.phase, .open)
        XCTAssertFalse(unlocked.ledger.lockedByParent)
        XCTAssertEqual(a4, [.unlock])
    }

    func testParentLockCancelsPendingRequest() {
        let (s, actions) = reduce(inPending(), .command(.lock), at(10, 2))
        XCTAssertEqual(s.phase, .locked)
        XCTAssertNil(s.request)
        XCTAssertEqual(actions, [.cancelRequest(requestID: "r1"), .lock])
    }

    func testUnlockWithoutBudgetStaysLocked() {
        let (parentLocked, _) = reduce(lockedWithRequest(), .command(.lock), at(10, 20))
        let (s, actions) = reduce(parentLocked, .command(.unlock), at(10, 21))
        XCTAssertEqual(s.phase, .locked)
        XCTAssertFalse(s.ledger.lockedByParent)
        XCTAssertEqual(actions, [])
    }

    // MARK: asking while locked

    func testAskWhileLockedSendsRequestAndStaysLocked() {
        let (s, actions) = reduce(lockedNoRequest(), .askForTime(requestID: "r2"), at(10, 20))
        XCTAssertEqual(s.phase, .locked)
        XCTAssertEqual(s.request, PendingRequest(id: "r2", seconds: 1800, deadline: at(10, 30)))
        XCTAssertEqual(actions, [.sendTimeRequest(requestID: "r2", seconds: 1800)])
        XCTAssertEqual(Policy.askState(s, config: config), .waiting)
    }

    func testApproveWhileLockedUnlocks() {
        let (s1, _) = reduce(lockedNoRequest(), .askForTime(requestID: "r2"), at(10, 20))
        let (s, actions) = reduce(s1, .answer(requestID: "r2", approved: true), at(10, 21))
        XCTAssertEqual(s.phase, .open)
        XCTAssertEqual(s.ledger.extra, 1800)
        XCTAssertEqual(actions, [.requestResult(requestID: "r2", approved: true), .unlock])
    }

    func testDenyBlocksFurtherAsks() {
        let (s1, _) = reduce(lockedNoRequest(), .askForTime(requestID: "r2"), at(10, 20))
        let (s, actions) = reduce(s1, .answer(requestID: "r2", approved: false), at(10, 21))
        XCTAssertEqual(s.phase, .locked)
        XCTAssertEqual(s.askDenied, true)
        XCTAssertEqual(actions, [.requestResult(requestID: "r2", approved: false)])
        XCTAssertEqual(Policy.askState(s, config: config), .denied)

        let (s2, actions2) = reduce(s, .askForTime(requestID: "r3"), at(10, 30))
        XCTAssertEqual(s2, s)
        XCTAssertEqual(actions2, [])
    }

    func testDenyInPendingAlsoBlocks() {
        let (s, _) = reduce(inPending(), .answer(requestID: "r1", approved: false), at(10, 2))
        XCTAssertEqual(s.askDenied, true)
        XCTAssertEqual(Policy.askState(s, config: config), .denied)
    }

    func testParentTimeClearsDenial() {
        let (s1, _) = reduce(lockedNoRequest(), .askForTime(requestID: "r2"), at(10, 20))
        let (denied, _) = reduce(s1, .answer(requestID: "r2", approved: false), at(10, 21))

        let (sExtra, _) = reduce(denied, .command(.extra(seconds: 600)), at(10, 40))
        XCTAssertNil(sExtra.askDenied)

        let (sStudio, _) = reduce(denied, .command(.studio(seconds: 600)), at(10, 40))
        XCTAssertNil(sStudio.askDenied)

        let (sUnlock, _) = reduce(denied, .command(.unlock), at(10, 40))
        XCTAssertNil(sUnlock.askDenied)
        XCTAssertEqual(sUnlock.phase, .locked)
        XCTAssertEqual(Policy.askState(sUnlock, config: config), .available)
    }

    func testNoAskDuringParentLock() {
        let (s1, _) = reduce(lockedNoRequest(), .command(.lock), at(10, 10))
        let (s, actions) = reduce(s1, .askForTime(requestID: "r4"), at(10, 11))
        XCTAssertNil(s.request)
        XCTAssertEqual(actions, [])
        XCTAssertEqual(Policy.askState(s, config: config), .unavailable)
    }

    func testAskState() {
        XCTAssertEqual(Policy.askState(state(), config: config), .unavailable)
        XCTAssertEqual(Policy.askState(inGrace(), config: config), .available)
        XCTAssertEqual(Policy.askState(inPending(), config: config), .waiting)
        XCTAssertEqual(Policy.askState(lockedNoRequest(), config: config), .available)

        var noTelegram = config
        noTelegram.telegramBotToken = ""
        XCTAssertEqual(Policy.askState(lockedNoRequest(), config: noTelegram), .unavailable)
    }

    func testStateWithoutAskDeniedDecodes() throws {
        let state = lockedNoRequest()
        let data = try JSONEncoder().encode(state)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(json.contains("\"askDenied\""))
        XCTAssertEqual(try JSONDecoder().decode(PolicyState.self, from: data), state)
    }

    // MARK: midnight

    func testNewDayResetsEverything() {
        let (parentLocked, _) = reduce(inPending(), .command(.lock), at(10, 2))
        XCTAssertTrue(parentLocked.ledger.lockedByParent)
        let (s, actions) = reduce(lockedWithRequest(), .tick(seconds: 15, active: false),
                                  at(0, 0, day: 24))
        XCTAssertEqual(s, PolicyState(ledger: DayLedger(day: "2026-11-24")))
        XCTAssertEqual(actions, [.cancelRequest(requestID: "r1"), .unlock])
        let (s2, a2) = reduce(parentLocked, .tick(seconds: 15, active: true), at(0, 1, day: 24))
        XCTAssertEqual(s2, PolicyState(ledger: DayLedger(day: "2026-11-24", used: 15)))
        XCTAssertEqual(a2, [.unlock])
    }

    // MARK: lock confirmation and logout

    func testLogoutWhenLockIsNotConfirmed() {
        let locked = lockedWithRequest()
        let (early, a1) = reduce(locked, .tick(seconds: 15, active: true), at(10, 5, 15))
        XCTAssertEqual(a1, [])
        let (s, a2) = reduce(early, .tick(seconds: 15, active: true), at(10, 5, 30))
        XCTAssertEqual(a2, [.logout])
        XCTAssertEqual(s.lockSentAt, at(10, 5, 30))
        XCTAssertEqual(s.phase, .locked)
    }

    func testNoLogoutWhileAgentConfirms() {
        let (confirmed, a0) = reduce(lockedWithRequest(), .lockConfirmed, at(10, 5, 20))
        XCTAssertEqual(confirmed.lockConfirmedAt, at(10, 5, 20))
        XCTAssertEqual(a0, [])
        let (s1, a1) = reduce(confirmed, .tick(seconds: 15, active: true), at(10, 5, 45))
        XCTAssertEqual(a1, [])
        let (_, a2) = reduce(s1, .tick(seconds: 15, active: true), at(10, 6))
        XCTAssertEqual(a2, [.logout])
    }

    func testNoLogoutWhenNobodyIsActive() {
        let (_, actions) = reduce(lockedWithRequest(), .tick(seconds: 15, active: false), at(10, 30))
        XCTAssertEqual(actions, [])
    }

    func testLockConfirmedOutsideLockedIsIgnored() {
        let (s, actions) = reduce(state(), .lockConfirmed, at(9, 0))
        XCTAssertEqual(s, state())
        XCTAssertEqual(actions, [])
    }

    // MARK: persistence

    func testCodableRoundTrip() throws {
        let original = lockedWithRequest()
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(PolicyState.self, from: data), original)
    }
}
