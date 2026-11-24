import XCTest
@testable import FamilyTimerCore

final class WeeklyTests: XCTestCase {
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

    func testCounts() {
        let (p, _) = reduce(inGrace(), .askForTime(requestID: "r1"), at(10, 1))
        XCTAssertEqual(p.ledger.requests, 1)
        let (a, _) = reduce(p, .answer(requestID: "r1", approved: true, seconds: 300), at(10, 2))
        XCTAssertEqual(a.ledger.approved, 1)
        XCTAssertNil(a.ledger.denied)
        let (d, _) = reduce(inPending(), .answer(requestID: "r1", approved: false), at(10, 2))
        XCTAssertEqual(d.ledger.denied, 1)
        let (u, _) = reduce(inPending(), .answer(requestID: "zz", approved: true), at(10, 2))
        XCTAssertNil(u.ledger.approved)
    }

    func testOldStateDecodes() throws {
        let data = Data("{\"day\":\"2026-11-23\",\"used\":5,\"extra\":0,\"lockedByParent\":false}".utf8)
        let ledger = try JSONDecoder().decode(DayLedger.self, from: data)
        XCTAssertNil(ledger.requests)
        XCTAssertEqual(ledger.used, 5)
    }

    func testParse() {
        XCTAssertEqual(parseCommand("/settimana"), .success(.week))
        XCTAssertEqual(parseCommand("/week"), .success(.week))
        XCTAssertTrue(Replies.help(.it).contains("/settimana - riepilogo degli ultimi 7 giorni"))
    }

    func testHistory() {
        var h = History()
        h.record(DaySummary(day: "2026-11-20", used: 100))
        h.record(DaySummary(day: "2026-11-18", used: 50))
        h.record(DaySummary(day: "2026-11-20", used: 200))
        XCTAssertEqual(h.days.map(\.day), ["2026-11-18", "2026-11-20"])
        XCTAssertEqual(h.days[1].used, 200)

        for n in 1...31 {
            h.record(DaySummary(day: String(format: "2026-10-%02d", n)))
        }
        for n in 1...9 {
            h.record(DaySummary(day: String(format: "2026-09-%02d", n)))
        }
        for n in 1...9 {
            h.record(DaySummary(day: String(format: "2026-11-%02d", n)))
        }
        XCTAssertEqual(h.days.count, 35)
        XCTAssertEqual(h.days.first?.day, "2026-10-08")
        XCTAssertEqual(h.days.last?.day, "2026-11-20")
    }

    func testWeek() {
        let h = History(days: [DaySummary(day: "2026-11-17", used: 3600), DaySummary(day: "2026-11-22", used: 1800, minecraft: 900)])
        let w = h.week(ending: DaySummary(day: "2026-11-23", used: 600), calendar: calendar)
        XCTAssertEqual(w.map(\.day), ["2026-11-17", "2026-11-18", "2026-11-19", "2026-11-20", "2026-11-21", "2026-11-22", "2026-11-23"])
        XCTAssertEqual(w.map(\.used), [3600, 0, 0, 0, 0, 1800, 600])
    }

    func testWeeklyText() {
        let h = History(days: [DaySummary(day: "2026-11-17", used: 3600, extra: 1800, requests: 2, approved: 1, denied: 1), DaySummary(day: "2026-11-22", used: 1800, minecraft: 900)])
        let w = h.week(ending: DaySummary(day: "2026-11-23", used: 600), calendar: calendar)
        let entries = [UsageEntry(key: "app:com.mojang.minecraft", name: "Minecraft", seconds: 900), UsageEntry(key: "site:youtube.com", name: "youtube.com", seconds: 800), UsageEntry(key: "app:com.google.Chrome", name: "Chrome", seconds: 700)]
        let categories = ["app:com.mojang.minecraft": UsageCategory.games]
        let text = Replies.weekly(child: "Art", days: w, entries: entries, categories: categories, calendar: calendar, .it)
        let expected = "📊 Art, ultimi 7 giorni (17/11–23/11):\nComputer: 1h 40m in tutto, in media 14m al giorno\nMinecraft: 15m\nRichieste di tempo: 2 (1 sì, 1 no)\nTempo extra dato: 30m\nmar 1h 00m · mer 0m · gio 0m · ven 0m · sab 0m · dom 30m · lun 10m\nIn cima: 🎮 Minecraft 15m · 🌐 Chrome 11m"
        XCTAssertEqual(text, expected)

        let emptyH = History()
        let emptyW = emptyH.week(ending: DaySummary(day: "2026-11-23"), calendar: calendar)
        let emptyText = Replies.weekly(child: "Art", days: emptyW, entries: [], categories: [:], calendar: calendar, .en)
        let emptyExpected = "📊 Art, last 7 days (17/11–23/11):\nComputer: 0m in all, 0m a day on average\nTue 0m · Wed 0m · Thu 0m · Fri 0m · Sat 0m · Sun 0m · Mon 0m"
        XCTAssertEqual(emptyText, emptyExpected)
    }
}
