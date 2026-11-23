import XCTest
@testable import FamilyTimerCore

final class MinecraftTests: XCTestCase {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Rome")!
        return c
    }()

    let config = Config(childUser: "a", weekdayLimit: 3600, weekendLimit: 7200,
                        minecraftLimit: 2700, weekendMinecraftLimit: 3600,
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

    func testConfigParse() throws {
        let c1 = try Config.parse("CHILD_USER=a\nMINECRAFT_LIMIT=2700")
        XCTAssertEqual(c1.minecraftLimit, 2700)
        XCTAssertEqual(c1.weekendMinecraftLimit, 2700)

        let c2 = try Config.parse("CHILD_USER=a\nMINECRAFT_LIMIT=2700\nWEEKEND_MINECRAFT_LIMIT=3600")
        XCTAssertEqual(c2.minecraftLimit, 2700)
        XCTAssertEqual(c2.weekendMinecraftLimit, 3600)

        let c3 = try Config.parse("CHILD_USER=a")
        XCTAssertEqual(c3.minecraftLimit, 0)
        XCTAssertEqual(c3.weekendMinecraftLimit, 0)

        XCTAssertThrowsError(try Config.parse("CHILD_USER=a\nMINECRAFT_LIMIT=abc")) { error in
            XCTAssertEqual(error as? ConfigError, .invalidNumber(key: "MINECRAFT_LIMIT", value: "abc"))
        }

        let c4 = try Config.parse("CHILD_USER=a\nMINECRAFT_LIMIT=0")
        XCTAssertEqual(c4.minecraftLimit, 0)
        XCTAssertEqual(c4.weekendMinecraftLimit, 0)
    }

    func testCommands() {
        XCTAssertEqual(parseCommand("/minecraft 15m"), .success(.minecraft(seconds: 900)))
        XCTAssertEqual(parseCommand("/mc 30"), .success(.minecraft(seconds: 1800)))
        XCTAssertEqual(parseCommand("/minecraft"), .failure(.missingDuration("/minecraft")))

        let r1 = parseAddressedCommand("/minecraft 15m art")
        XCTAssertEqual(r1.result, .success(.minecraft(seconds: 900)))
        XCTAssertEqual(r1.target, "art")

        let r2 = parseAddressedCommand("/mc art 15")
        XCTAssertEqual(r2.result, .success(.minecraft(seconds: 900)))
        XCTAssertEqual(r2.target, "art")
    }

    func testRemainingWeekday() {
        let state = PolicyState(ledger: DayLedger(day: "2026-11-23"))
        XCTAssertEqual(Policy.minecraftRemaining(state, played: 600, now: at(9, 0), config: config, calendar: calendar), 2100)
        XCTAssertEqual(Policy.minecraftRemaining(state, played: 3000, now: at(9, 0), config: config, calendar: calendar), 0)
    }

    func testRemainingWeekend() {
        let state = PolicyState(ledger: DayLedger(day: "2026-11-28"))
        XCTAssertEqual(Policy.minecraftRemaining(state, played: 600, now: at(9, 0, day: 28), config: config, calendar: calendar), 3000)
    }

    func testNoLimit() {
        var noLimitConfig = config
        noLimitConfig.minecraftLimit = 0
        noLimitConfig.weekendMinecraftLimit = 0
        let state = PolicyState(ledger: DayLedger(day: "2026-11-23"))
        XCTAssertNil(Policy.minecraftRemaining(state, played: 600, now: at(9, 0), config: noLimitConfig, calendar: calendar))
    }

    func testExtra() {
        let state = PolicyState(ledger: DayLedger(day: "2026-11-23"))
        let (s1, actions1) = reduce(state, .command(.minecraft(seconds: 900)), at(9, 0))
        XCTAssertEqual(actions1, [])
        XCTAssertEqual(s1.phase, .open)
        XCTAssertEqual(s1.ledger.minecraftExtra, 900)
        XCTAssertEqual(s1.ledger.extra, 0)
        XCTAssertEqual(Policy.minecraftRemaining(s1, played: 3000, now: at(9, 0), config: config, calendar: calendar), 600)

        let (s2, _) = reduce(s1, .command(.minecraft(seconds: 900)), at(9, 0))
        XCTAssertEqual(s2.ledger.minecraftExtra, 1800)
    }

    func testExtraDoesNotChangeMinecraft() {
        let state = PolicyState(ledger: DayLedger(day: "2026-11-23"))
        let (s, _) = reduce(state, .command(.extra(seconds: 1800)), at(9, 0))
        XCTAssertEqual(Policy.minecraftRemaining(s, played: 600, now: at(9, 0), config: config, calendar: calendar), 2100)
    }

    func testStudio() {
        let state = PolicyState(ledger: DayLedger(day: "2026-11-23"))
        let (s, _) = reduce(state, .command(.studio(seconds: 3600)), at(9, 0))
        XCTAssertEqual(Policy.minecraftRemaining(s, played: 0, now: at(9, 30), config: config, calendar: calendar), 0)
        XCTAssertEqual(Policy.minecraftRemaining(s, played: 0, now: at(10, 30), config: config, calendar: calendar), 2700)
    }

    func testCodableRoundTrip() throws {
        let ledger = DayLedger(day: "2026-11-23")
        let data = try JSONEncoder().encode(ledger)
        let decoded = try JSONDecoder().decode(DayLedger.self, from: data)
        XCTAssertNil(decoded.minecraftExtra)
    }
}
