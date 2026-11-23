import XCTest
@testable import FamilyTimerCore

final class AnswerTests: XCTestCase {
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

    func testApproveWithAmount() {
        let (s, actions) = reduce(inPending(), .answer(requestID: "r1", approved: true, seconds: 300), at(10, 2))
        XCTAssertEqual(s.phase, .open)
        XCTAssertEqual(s.ledger.extra, 300)
        XCTAssertNil(s.request)
        XCTAssertEqual(actions, [.requestResult(requestID: "r1", approved: true)])
    }

    func testApproveWithoutAmountUsesRequest() {
        let (s, _) = reduce(inPending(), .answer(requestID: "r1", approved: true), at(10, 2))
        XCTAssertEqual(s.ledger.extra, 1800)
    }

    func testLateApproveWithAmount() {
        let (s, actions) = reduce(lockedWithRequest(), .answer(requestID: "r1", approved: true, seconds: 3600), at(10, 20))
        XCTAssertEqual(s.phase, .open)
        XCTAssertEqual(s.ledger.extra, 3600)
        XCTAssertEqual(actions, [.requestResult(requestID: "r1", approved: true), .unlock])
    }

    func testParseAnswerData() {
        XCTAssertEqual(parseAnswerData("approve:ab12"), AnswerData(requestID: "ab12", approved: true))
        XCTAssertEqual(parseAnswerData("deny:ab12"), AnswerData(requestID: "ab12", approved: false))
        XCTAssertEqual(parseAnswerData("approve:ab12:300"), AnswerData(requestID: "ab12", approved: true, seconds: 300))
        XCTAssertNil(parseAnswerData("deny:ab12:300"))
        XCTAssertNil(parseAnswerData("approve:ab12:0"))
        XCTAssertNil(parseAnswerData("approve:ab12:x"))
        XCTAssertNil(parseAnswerData("approve:"))
        XCTAssertNil(parseAnswerData("cat:app:x:games"))
        XCTAssertNil(parseAnswerData("approve"))
        XCTAssertNil(parseAnswerData("approve:ab12:300:1"))
    }

    func testTexts() {
        XCTAssertEqual(Replies.approveChoices, [120, 300, 1800, 3600])
        XCTAssertEqual(Replies.approveChoiceButton(seconds: 120), "✅ 2m")
        XCTAssertEqual(Replies.approveChoiceButton(seconds: 1800), "✅ 30m")
        XCTAssertEqual(Replies.approveChoiceButton(seconds: 3600), "✅ 1h")
        XCTAssertEqual(Replies.decided("Q", approved: true, by: "Ann", .it, seconds: 300), "Q\n✅ Approvato (+5m) da Ann.")
        XCTAssertEqual(Replies.decided("Q", approved: true, by: "", .en, seconds: 3600), "Q\n✅ Approved (+1h 00m).")
        XCTAssertEqual(Replies.decided("Q", approved: false, by: "Ann", .it, seconds: 300), "Q\n❌ Negato da Ann.")
    }
}
