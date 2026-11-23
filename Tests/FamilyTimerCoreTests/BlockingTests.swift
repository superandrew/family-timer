import XCTest
@testable import FamilyTimerCore

final class BlockingTests: XCTestCase {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Rome")!
        return c
    }()

    let config = Config(childUser: "a", weekdayLimit: 3600, weekendLimit: 7200,
                        minecraftLimit: 2700, weekendMinecraftLimit: 3600,
                        extensionTime: 1800, graceTime: 300, approvalTimeout: 600,
                        telegramBotToken: "token", telegramChatID: "-100")

    func at(_ h: Int, _ m: Int, _ s: Int = 0, day: Int = 23) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day,
                                           hour: h, minute: m, second: s))!
    }

    func testReason() {
        // Minecraft with 0 left, not in studio -> .minecraftOver
        XCTAssertEqual(Blocking.reason(appKey: "app:com.mojang.minecraft", category: nil, minecraftRemaining: 0, inStudio: false), .minecraftOver)
        // Minecraft with 600 left -> nil
        XCTAssertNil(Blocking.reason(appKey: "app:com.mojang.minecraft", category: nil, minecraftRemaining: 600, inStudio: false))
        // Minecraft with nil (no limit) -> nil
        XCTAssertNil(Blocking.reason(appKey: "app:com.mojang.minecraft", category: nil, minecraftRemaining: nil, inStudio: false))
        // Minecraft in studio with 600 left -> .studio
        XCTAssertEqual(Blocking.reason(appKey: "app:com.mojang.minecraft", category: nil, minecraftRemaining: 600, inStudio: true), .studio)
        // Terminal category .coding in studio -> .studio
        XCTAssertEqual(Blocking.reason(appKey: "app:com.apple.Terminal", category: .coding, minecraftRemaining: nil, inStudio: true), .studio)
        // Terminal category .coding not in studio -> nil
        XCTAssertNil(Blocking.reason(appKey: "app:com.apple.Terminal", category: .coding, minecraftRemaining: nil, inStudio: false))
        // Category .video in studio -> nil
        XCTAssertNil(Blocking.reason(appKey: "app:com.apple.Terminal", category: .video, minecraftRemaining: nil, inStudio: true))
        // Category nil in studio -> nil
        XCTAssertNil(Blocking.reason(appKey: "app:com.apple.Terminal", category: nil, minecraftRemaining: nil, inStudio: true))
        // Browser category .games in studio -> nil
        XCTAssertNil(Blocking.reason(appKey: "app:com.google.Chrome", category: .games, minecraftRemaining: nil, inStudio: true))
        // Site category .coding in studio -> nil
        XCTAssertNil(Blocking.reason(appKey: "site:github.com", category: .coding, minecraftRemaining: nil, inStudio: true))
    }

    func testWire() throws {
        let msg = DaemonMessage(type: .close, app: "app:com.mojang.minecraft", reason: .minecraftOver)
        let data = Wire.encode(msg)
        let expected = "{\"app\":\"app:com.mojang.minecraft\",\"reason\":\"minecraft_over\",\"type\":\"close\"}\n".data(using: .utf8)!
        XCTAssertEqual(data, expected)
        let decoded = try JSONDecoder().decode(DaemonMessage.self, from: data)
        XCTAssertEqual(decoded, msg)

        let stateMsg = DaemonMessage(type: .state, minecraftRemaining: 600)
        let stateData = Wire.encode(stateMsg)
        let stateDecoded = try JSONDecoder().decode(DaemonMessage.self, from: stateData)
        XCTAssertEqual(stateDecoded, stateMsg)
    }

    func testTexts() {
        XCTAssertEqual(AgentTexts.minecraftWarning(minutes: 5, .it), "Minecraft: mancano 5 minuti per oggi.")
        XCTAssertEqual(AgentTexts.closed(app: "OpenCode", reason: .studio, .it), "È tempo di studio: «OpenCode» si chiude.")
    }

    func testStatus() {
        var testConfig = config
        testConfig.language = .it
        testConfig.childNames = ["Art"]

        let state = PolicyState(ledger: DayLedger(day: "2026-11-23", used: 600))
        let status = Replies.status(state, now: at(10, 0), config: testConfig, calendar: calendar, minecraftPlayed: 1200)
        XCTAssertTrue(status.contains("Minecraft: giocati 20m su 45m. Rimasti: 25m."))

        let statusNoMinecraft = Replies.status(state, now: at(10, 0), config: testConfig, calendar: calendar)
        XCTAssertFalse(statusNoMinecraft.contains("Minecraft"))
    }

    func testReply() {
        var testConfig = config
        testConfig.language = .it
        testConfig.childNames = ["Art"]

        let state = PolicyState(ledger: DayLedger(day: "2026-11-23"))
        let (s, _) = Policy.reduce(state, .command(.minecraft(seconds: 900)), now: at(10, 0), config: testConfig, calendar: calendar)
        let reply = Replies.reply(to: .minecraft(seconds: 900), after: s, now: at(10, 0), config: testConfig, calendar: calendar, minecraftPlayed: 2700)
        XCTAssertEqual(reply, "Art: Minecraft: aggiunti 15m. Rimasti: 15m.")
    }

    func testHelp() {
        var testConfig = config
        testConfig.language = .it
        let help = Replies.help(.it)
        XCTAssertTrue(help.contains("/minecraft 15m - più Minecraft oggi"))
    }
}
