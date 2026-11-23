import XCTest
@testable import FamilyTimerCore

final class MenuTests: XCTestCase {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Rome")!
        return c
    }()

    let config = Config(childUser: "a", weekdayLimit: 3600, weekendLimit: 7200,
                        minecraftLimit: 2700, weekendMinecraftLimit: 3600,
                        language: .it)

    let today = [
        UsageEntry(key: "app:com.mojang.minecraft", name: "Minecraft", seconds: 1200),
        UsageEntry(key: "site:youtube.com", name: "youtube.com", seconds: 600),
        UsageEntry(key: "app:com.google.Chrome", name: "Chrome", seconds: 300),
        UsageEntry(key: "app:com.apple.Terminal", name: "Terminal", seconds: 120),
        UsageEntry(key: "app:com.apple.Notes", name: "Note", seconds: 90),
    ]
    let categories: [String: UsageCategory] = ["app:com.mojang.minecraft": .games, "app:com.apple.Terminal": .coding]

    func at(_ h: Int, _ m: Int, _ s: Int = 0, day: Int = 23) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day,
                                           hour: h, minute: m, second: s))!
    }

    func testLines() {
        let s = PolicyState(ledger: DayLedger(day: "2026-11-23", used: 600))
        let lines = AgentTexts.menuLines(s, now: at(10, 0), config: config, calendar: calendar,
                                         minecraftPlayed: 1200, today: today, categories: categories)
        XCTAssertEqual(lines, [
            "Computer: restano 50m (usati 10m su 1h 00m)",
            "Minecraft: restano 25m (giocati 20m su 45m)",
            "Oggi:",
            "🎮 Minecraft 20m",
            "🌐 Chrome 5m",
            "💻 Terminal 2m"
        ])
    }

    func testExtrasAndNoMinecraft() {
        var ledger = DayLedger(day: "2026-11-23", used: 600, extra: 1800)
        ledger.minecraftExtra = 900
        let s = PolicyState(ledger: ledger)

        let lines = AgentTexts.menuLines(s, now: at(10, 0), config: config, calendar: calendar,
                                         minecraftPlayed: 3600, today: [], categories: categories)
        XCTAssertEqual(lines, [
            "Computer: restano 1h 20m (usati 10m su 1h 30m)",
            "Minecraft: restano 0m (giocati 1h 00m su 1h 00m)"
        ])

        let linesNoMc = AgentTexts.menuLines(s, now: at(10, 0), config: config, calendar: calendar,
                                             minecraftPlayed: nil, today: [], categories: categories)
        XCTAssertEqual(linesNoMc, [
            "Computer: restano 1h 20m (usati 10m su 1h 30m)"
        ])
    }

    func testStudio() {
        let s = PolicyState(ledger: DayLedger(day: "2026-11-23", used: 600, studioUntil: at(11, 30)))
        let lines = AgentTexts.menuLines(s, now: at(10, 0), config: config, calendar: calendar,
                                         minecraftPlayed: 0, today: [], categories: categories)
        XCTAssertEqual(lines, [
            "Computer: restano 50m (usati 10m su 1h 00m)",
            "Minecraft: restano 0m (giocati 0m su 45m)",
            "Studio fino alle 11:30"
        ])
    }

    func testTitle() {
        XCTAssertEqual(AgentTexts.menuTitle(remaining: 1500, phase: .open, graceRemaining: nil, .it), "⏱ 25m")
        XCTAssertEqual(AgentTexts.menuTitle(remaining: 1500, phase: .open, graceRemaining: nil, .it, minecraftRemaining: 600), "⏱ 25m ⛏ 10m")
        XCTAssertEqual(AgentTexts.menuTitle(remaining: 0, phase: .locked, graceRemaining: nil, .it, minecraftRemaining: 600), "⏱ bloccato")
    }

    func testWire() throws {
        let msg = DaemonMessage(type: .state, remaining: 60, menu: ["a", "b"])
        let data = Wire.encode(msg)
        let decoded = try JSONDecoder().decode(DaemonMessage.self, from: data.dropLast())
        XCTAssertEqual(decoded, msg)
        let str = String(data: data, encoding: .utf8)!
        XCTAssertTrue(str.contains("\"menu\":[\"a\",\"b\"]"))
    }
}
