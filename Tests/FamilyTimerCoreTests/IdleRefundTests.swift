import XCTest
@testable import FamilyTimerCore

final class IdleRefundTests: XCTestCase {
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

    func testLedgerRefund() {
        var ledger = DayLedger(day: "2026-11-23", used: 100)
        ledger.refund(seconds: 30)
        XCTAssertEqual(ledger.used, 70)
        ledger.refund(seconds: 500)
        XCTAssertEqual(ledger.used, 0)
        ledger.refund(seconds: -5)
        XCTAssertEqual(ledger.used, 0)
    }

    func testPolicyRefundInOpen() {
        let (s, actions) = reduce(state(used: 1000), .refund(seconds: 120), at(10, 0))
        XCTAssertEqual(s.ledger.used, 880)
        XCTAssertEqual(s.phase, .open)
        XCTAssertTrue(actions.isEmpty)
    }

    func testPolicyRefundIgnoredOutsideOpen() {
        for phase in [Phase.grace, .pending, .locked] {
            let (s, _) = reduce(state(used: 3600, phase: phase), .refund(seconds: 120), at(10, 0))
            XCTAssertEqual(s.ledger.used, 3600)
        }
    }

    func testUsageSubtract() {
        var log = UsageLog()
        log.add(Frontmost(bundleID: "a", name: "A"), seconds: 100, day: "2026-11-23")
        log.subtract(key: "app:a", seconds: 30, day: "2026-11-23")
        XCTAssertEqual(log.total(for: "app:a"), 70)
        log.subtract(key: "app:a", seconds: 100, day: "2026-11-23")
        XCTAssertNil(log.days[0].seconds["app:a"])
        log.subtract(key: "app:a", seconds: 10, day: "2026-11-22")
        log.subtract(key: "app:zz", seconds: 10, day: "2026-11-23")
    }

    func testRunIsRefunded() {
        var r = IdleRefund()
        r.counted(seconds: 15, idle: 3, keys: ["app:a"], day: "d")
        r.counted(seconds: 15, idle: 18, keys: ["app:a", "site:x"], day: "d")
        r.counted(seconds: 15, idle: 33, keys: ["app:a"], day: "d")
        let result = r.take()
        XCTAssertEqual(result?.seconds, 30)
        XCTAssertEqual(result?.keys, ["app:a": 30, "site:x": 15])
        XCTAssertEqual(result?.day, "d")
        XCTAssertNil(r.take())
    }

    func testInputResetsRun() {
        var r = IdleRefund()
        r.counted(seconds: 15, idle: 20, keys: ["app:a"], day: "d")
        r.counted(seconds: 15, idle: 35, keys: ["app:a"], day: "d")
        r.counted(seconds: 15, idle: 2, keys: ["app:a"], day: "d")
        XCTAssertNil(r.take())
    }

    func testNewDayResetsRun() {
        var r = IdleRefund()
        r.counted(seconds: 15, idle: 20, keys: ["app:a"], day: "d1")
        r.counted(seconds: 15, idle: 35, keys: ["app:a"], day: "d2")
        let result = r.take()
        XCTAssertEqual(result?.seconds, 15)
        XCTAssertEqual(result?.day, "d2")
    }

    func testTakeWithoutTicks() {
        var r = IdleRefund()
        XCTAssertNil(r.take())
    }
}
