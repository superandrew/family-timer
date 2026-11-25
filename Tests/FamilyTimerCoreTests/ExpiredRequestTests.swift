import XCTest
@testable import FamilyTimerCore

final class ExpiredRequestTests: XCTestCase {
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

    func askState(_ s: PolicyState, _ now: Date) -> AskState {
        Policy.askState(s, config: config, now: now, calendar: calendar)
    }

    func testAskStateAfterDeadline() {
        let s = lockedWithRequest()
        XCTAssertEqual(askState(s, at(10, 10)), .waiting)
        XCTAssertEqual(askState(s, at(10, 11)), .available)
        XCTAssertEqual(Policy.askState(s, config: config), .waiting)
    }

    func testAskBeforeDeadlineIsIgnored() {
        let s = lockedWithRequest()
        let (s2, actions) = reduce(s, .askForTime(requestID: "r2"), at(10, 10))
        XCTAssertEqual(s2, s)
        XCTAssertEqual(actions, [])
    }

    func testAskAfterDeadlineReplacesRequest() {
        let (s, actions) = reduce(lockedWithRequest(), .askForTime(requestID: "r2"), at(10, 20))
        XCTAssertEqual(s.phase, .locked)
        XCTAssertEqual(s.request, PendingRequest(id: "r2", seconds: 1800, deadline: at(10, 30)))
        XCTAssertEqual(actions, [.cancelRequest(requestID: "r1"), .sendTimeRequest(requestID: "r2", seconds: 1800)])
        XCTAssertEqual(askState(s, at(10, 21)), .waiting)
    }

    func testOldApproveAfterNewAskIsIgnored() {
        let (s1, _) = reduce(lockedWithRequest(), .askForTime(requestID: "r2"), at(10, 20))
        let (s, actions) = reduce(s1, .answer(requestID: "r1", approved: true), at(10, 21))
        XCTAssertEqual(s, s1)
        XCTAssertEqual(actions, [])
    }

    func testLateApproveStillWorksWithoutNewAsk() {
        let (s, actions) = reduce(lockedWithRequest(), .answer(requestID: "r1", approved: true), at(10, 30))
        XCTAssertEqual(s.phase, .open)
        XCTAssertEqual(s.ledger.extra, 1800)
        XCTAssertNil(s.request)
        XCTAssertEqual(actions, [.requestResult(requestID: "r1", approved: true), .unlock])
    }

    func testExpiredEarlyRequestDoesNotBlockGrace() {
        let (s1, _) = reduce(state(used: 2700), .askForTime(requestID: "r1"), at(9, 0))
        let (s2, _) = reduce(s1, .tick(seconds: 900, active: true), at(9, 20))
        XCTAssertEqual(s2.phase, .grace)
        XCTAssertEqual(askState(s2, at(9, 20)), .available)
        let (s3, actions) = reduce(s2, .askForTime(requestID: "r2"), at(9, 21))
        XCTAssertEqual(s3.phase, .pending)
        XCTAssertEqual(s3.request?.id, "r2")
        XCTAssertEqual(actions, [.cancelRequest(requestID: "r1"), .sendTimeRequest(requestID: "r2", seconds: 1800)])
    }
}
