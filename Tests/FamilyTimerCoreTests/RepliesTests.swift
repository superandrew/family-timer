import XCTest
@testable import FamilyTimerCore

final class RepliesTests: XCTestCase {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Rome")!
        return c
    }()

    let config = Config(childUser: "arthur", weekdayLimit: 3600, weekendLimit: 7200)

    func at(_ h: Int, _ m: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: h, minute: m))!
    }

    func testDuration() {
        XCTAssertEqual(Replies.duration(0), "0m")
        XCTAssertEqual(Replies.duration(59), "0m")
        XCTAssertEqual(Replies.duration(45 * 60), "45m")
        XCTAssertEqual(Replies.duration(3600), "1h 00m")
        XCTAssertEqual(Replies.duration(3600 + 5 * 60 + 30), "1h 05m")
        XCTAssertEqual(Replies.duration(-10), "0m")
    }

    func testClock() {
        XCTAssertEqual(Replies.clock(at(9, 5), calendar: calendar), "09:05")
    }

    func testStatus() {
        var state = PolicyState(ledger: DayLedger(day: "2026-11-23", used: 2700, extra: 1800))
        XCTAssertEqual(Replies.status(state, now: at(10, 0), config: config, calendar: calendar),
                       "arthur: used 45m of 1h 00m + 30m extra.\nRemaining: 45m. State: open.")
        state.ledger.studioUntil = at(11, 30)
        state.ledger.lockedByParent = true
        state.phase = .locked
        XCTAssertEqual(Replies.status(state, now: at(10, 0), config: config, calendar: calendar),
                       "arthur: used 45m of 1h 00m + 30m extra.\nRemaining: 45m. State: locked.\n"
                       + "Study time until 11:30.\nLocked by a parent until midnight or /unlock.")
    }

    func testReplies() {
        let open = PolicyState(ledger: DayLedger(day: "2026-11-23", used: 3000, extra: 600))
        XCTAssertEqual(Replies.reply(to: .extra(seconds: 600), after: open, now: at(10, 0),
                                     config: config, calendar: calendar),
                       "arthur: Added 10m. Remaining: 20m.")
        let locked = PolicyState(ledger: DayLedger(day: "2026-11-23", used: 3600), phase: .locked)
        XCTAssertEqual(Replies.reply(to: .unlock, after: locked, now: at(10, 0),
                                     config: config, calendar: calendar),
                       "arthur: Parent lock removed, but no time is left: still locked. Use /extra or /studio.")
    }

    func testErrorsAndRequest() {
        XCTAssertEqual(Replies.error(.missingDuration("/extra"), .en),
                       "/extra needs a duration, for example /extra 30 or /extra 1h30.")
        XCTAssertEqual(Replies.request(child: "arthur", seconds: 1800, .en),
                       "⏰ arthur has used today's time and asks for 30m more.")
        XCTAssertEqual(Replies.decided("Q", approved: true, by: "Ann", .en), "Q\n✅ Approved by Ann.")
        XCTAssertEqual(Replies.decided("Q", approved: false, by: "", .en), "Q\n❌ Denied.")
    }

    func testDisplayName() {
        var named = config
        named.childNames = ["Art", "arthur"]
        let state = PolicyState(ledger: DayLedger(day: "2026-11-23", used: 600))
        XCTAssertEqual(Replies.reply(to: .lock, after: state, now: at(10, 0), config: named, calendar: calendar),
                       "Art: Locked until midnight or /unlock.")
        XCTAssertTrue(Replies.status(state, now: at(10, 0), config: named, calendar: calendar).hasPrefix("Art: used 10m"))
    }

    func testItalian() {
        var it = config
        it.language = .it
        let state = PolicyState(ledger: DayLedger(day: "2026-11-23", used: 2700, extra: 1800,
                                                  studioUntil: at(11, 30), lockedByParent: true),
                                phase: .locked)
        XCTAssertEqual(Replies.status(state, now: at(10, 0), config: it, calendar: calendar),
                       "arthur: usati 45m su 1h 00m + 30m extra.\nRimasti: 45m. Stato: bloccato.\n"
                       + "Studio fino alle 11:30.\nBloccato da un genitore fino a mezzanotte o /unlock.")
        XCTAssertEqual(Replies.reply(to: .extra(seconds: 600), after: state, now: at(10, 0),
                                     config: it, calendar: calendar),
                       "arthur: Aggiunti 10m. Rimasti: 45m. Resta bloccato da /lock.")
        XCTAssertEqual(Replies.error(.invalidDuration("xx"), .it),
                       "\"xx\" non è una durata tra 1 minuto e 12 ore (30, 45m, 2h, 1h30).")
        XCTAssertEqual(Replies.request(child: "arthur", seconds: 1800, .it),
                       "⏰ arthur ha finito il tempo di oggi e chiede altri 30m.")
        XCTAssertEqual(Replies.decided("Q", approved: false, by: "Ann", .it), "Q\n❌ Negato da Ann.")
        XCTAssertTrue(Replies.help(.it).hasPrefix("/status - tempo usato e rimasto oggi\n"))
    }

    func testAgentLines() {
        var it = config
        it.language = .it
        let state = PolicyState(ledger: DayLedger(day: "2026-11-23", used: 600))
        XCTAssertTrue(Replies.status(state, now: at(10, 0), config: config, calendar: calendar,
                                     agentConnected: true).hasSuffix("\nMenu bar app: connected."))
        XCTAssertTrue(Replies.reply(to: .status, after: state, now: at(10, 0), config: it, calendar: calendar,
                                    agentConnected: false).hasSuffix("\nApp nella barra: non collegata."))
        XCTAssertFalse(Replies.status(state, now: at(10, 0), config: config, calendar: calendar).contains("app"))
        XCTAssertEqual(Replies.agentBack(child: "arthur", .it), "✅ arthur: l'app nella barra è di nuovo collegata.")
        XCTAssertTrue(Replies.agentMissing(child: "arthur", .en).hasPrefix("⚠️ arthur: the menu bar app"))
    }

    func testUsage() {
        let entries = [UsageEntry(key: "app:com.mojang.minecraft", name: "Minecraft", seconds: 15000),
                       UsageEntry(key: "site:youtube.com", name: "youtube.com", seconds: 4200),
                       UsageEntry(key: "app:com.apple.Safari", name: "Safari", seconds: 4500)]
        let categories: [String: UsageCategory] = ["app:com.mojang.minecraft": .games]

        XCTAssertEqual(
            Replies.usage(entries, categories: categories, child: "arthur", days: 7, limit: 10, .it),
            "arthur, ultimi 7 giorni:\nApp:\n🎮 Minecraft 4h 10m\n❓ Safari 1h 15m\nSiti:\n❓ youtube.com 1h 10m"
        )
        XCTAssertEqual(
            Replies.usage(entries, categories: categories, child: "arthur", days: 7, limit: 1, .en),
            "arthur, last 7 days:\nApps:\n🎮 Minecraft 4h 10m\nSites:\n❓ youtube.com 1h 10m"
        )
        XCTAssertEqual(
            Replies.usage([], categories: [:], child: "arthur", days: 1, limit: 10, .it),
            "arthur, oggi:\nAncora nessun dato."
        )
        XCTAssertEqual(Replies.classifyPrompt(name: "Minecraft", seconds: 600, .it), "Che cos'è «Minecraft» (10m)?")
        XCTAssertEqual(Replies.classified(name: "Minecraft", category: .games, by: "Andrea", .it), "«Minecraft»: 🎮 giochi (Andrea)")
        XCTAssertEqual(Replies.categoryEmoji(nil), "❓")
        XCTAssertEqual(Replies.categoryLabel(.study, .en), "📚 study")
    }
}
