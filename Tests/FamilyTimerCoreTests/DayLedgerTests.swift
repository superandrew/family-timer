import XCTest
@testable import FamilyTimerCore

final class DayLedgerTests: XCTestCase {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Rome")!
        return c
    }()

    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    func testDayKey() {
        XCTAssertEqual(DayLedger.dayKey(date(2026, 11, 23, 10, 0), calendar: calendar), "2026-11-23")
        XCTAssertEqual(DayLedger.dayKey(date(2026, 11, 23, 23, 59), calendar: calendar), "2026-11-23")
        XCTAssertEqual(DayLedger.dayKey(date(2026, 11, 24, 0, 0), calendar: calendar), "2026-11-24")
    }

    func testBudget() {
        let config = Config(childUser: "a", weekdayLimit: 3600, weekendLimit: 7200)
        XCTAssertEqual(DayLedger.budget(for: date(2026, 11, 23, 10, 0), config: config, calendar: calendar), 3600)
        XCTAssertEqual(DayLedger.budget(for: date(2026, 11, 21, 10, 0), config: config, calendar: calendar), 7200)
        XCTAssertEqual(DayLedger.budget(for: date(2026, 11, 22, 10, 0), config: config, calendar: calendar), 7200)
    }

    func testFresh() {
        XCTAssertEqual(DayLedger.fresh(for: date(2026, 11, 23, 10, 0), calendar: calendar), DayLedger(day: "2026-11-23"))
    }

    func testTick() {
        var ledger = DayLedger.fresh(for: date(2026, 11, 23, 10, 0), calendar: calendar)
        let now = date(2026, 11, 23, 10, 0)
        ledger.tick(seconds: 15, active: true, now: now)
        ledger.tick(seconds: 15, active: true, now: now)
        XCTAssertEqual(ledger.used, 30)
        ledger.tick(seconds: 15, active: false, now: now)
        XCTAssertEqual(ledger.used, 30)
    }

    func testStudio() {
        var ledger = DayLedger.fresh(for: date(2026, 11, 23, 10, 0), calendar: calendar)
        let start = date(2026, 11, 23, 10, 0)
        ledger.startStudio(seconds: 7200, now: start)
        XCTAssertEqual(ledger.studioUntil, date(2026, 11, 23, 12, 0))
        XCTAssertTrue(ledger.inStudio(at: date(2026, 11, 23, 11, 59)))
        XCTAssertFalse(ledger.inStudio(at: date(2026, 11, 23, 12, 0)))
        ledger.tick(seconds: 15, active: true, now: date(2026, 11, 23, 11, 0))
        XCTAssertEqual(ledger.used, 0)
        ledger.tick(seconds: 15, active: true, now: date(2026, 11, 23, 12, 1))
        XCTAssertEqual(ledger.used, 15)
    }

    func testRemaining() {
        XCTAssertEqual(DayLedger(day: "x", used: 3000).remaining(budget: 3600), 600)
        XCTAssertEqual(DayLedger(day: "x", used: 4000).remaining(budget: 3600), 0)
        XCTAssertEqual(DayLedger(day: "x", used: 4000, extra: 1800).remaining(budget: 3600), 1400)
    }

    func testGrantExtra() {
        var ledger = DayLedger(day: "x")
        ledger.grantExtra(seconds: 1800)
        ledger.grantExtra(seconds: 1800)
        XCTAssertEqual(ledger.extra, 3600)
    }

    func testRolled() {
        let ledger = DayLedger(day: "2026-11-23", used: 500, lockedByParent: true)
        XCTAssertEqual(ledger.rolled(to: date(2026, 11, 23, 22, 0), calendar: calendar), ledger)
        XCTAssertEqual(ledger.rolled(to: date(2026, 11, 24, 0, 1), calendar: calendar), DayLedger(day: "2026-11-24"))
    }

    func testCodableRoundTrip() {
        let original = DayLedger(day: "2026-11-23", used: 10, extra: 20,
                                 studioUntil: date(2026, 11, 23, 12, 0), lockedByParent: true)
        let data = try! JSONEncoder().encode(original)
        let decoded = try! JSONDecoder().decode(DayLedger.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}
