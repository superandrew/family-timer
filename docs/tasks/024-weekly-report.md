+++
id = "024"
title = "Weekly report: day summaries, request counts, /settimana, report text"
edit = ["Sources/FamilyTimerCore/DayLedger.swift", "Sources/FamilyTimerCore/Policy.swift", "Sources/FamilyTimerCore/Commands.swift", "Sources/FamilyTimerCore/Replies.swift", "Sources/FamilyTimerCore/History.swift", "Tests/FamilyTimerCoreTests/WeeklyTests.swift"]
read = ["Tests/FamilyTimerCoreTests/PolicyTests.swift", "Sources/FamilyTimerCore/Usage.swift"]
checks = ["test -s Sources/FamilyTimerCore/History.swift && test -s Tests/FamilyTimerCoreTests/WeeklyTests.swift", "swift build", "swift test --filter WeeklyTests", "swift test", "git add -N -- Sources/FamilyTimerCore/History.swift Tests/FamilyTimerCoreTests/WeeklyTests.swift && git --no-pager diff --check HEAD"]
commit = "feat(core): weekly report: day summaries, request counts, /settimana and its text"
edit_format = "diff"
+++

# 024 - Weekly report

On Sunday evening, and on `/settimana`, the parents get a summary of the last 7 days per
child: computer time, Minecraft, time requests and their outcome, time per day, top apps.
The ledger only knows today, so at every new day the daemon keeps a summary of the day that
ended. This card writes the pure parts. Existing tests must keep passing without changes.

## Sources/FamilyTimerCore/DayLedger.swift

1. Three new properties right after `public var minecraftExtra: Int?` (optional, so old state
   files still decode; NOT added to the init):

        /// Time requests sent today, and how they were answered.
        public var requests: Int?
        public var approved: Int?
        public var denied: Int?

2. Two new methods right after `grantMinecraftExtra`:

        public mutating func countRequest() {
            requests = (requests ?? 0) + 1
        }

        public mutating func countAnswer(approved yes: Bool) {
            if yes {
                approved = (approved ?? 0) + 1
            } else {
                denied = (denied ?? 0) + 1
            }
        }

## Sources/FamilyTimerCore/Policy.swift

1. In `reduce`, `case let .askForTime(requestID):`, right before the line
   `s.request = PendingRequest(` add `s.ledger.countRequest()`.
2. In `case let .answer(requestID, approved, seconds):`, right after the line `s.request = nil`
   add `s.ledger.countAnswer(approved: approved)`.
3. In `case let .command(command):` the line `case .status, .help, .apps:` becomes
   `case .status, .help, .apps, .week:`.

## Sources/FamilyTimerCore/Commands.swift

1. `enum Command`: new case `week` after `case apps(days: Int)`.
2. `parseCommand`: right after the `case "/oggi", "/today":` branch (and its return), add

        case "/settimana", "/week":
            return .success(.week)

## Sources/FamilyTimerCore/History.swift (new; its SEARCH section is empty)

    import Foundation

    /// One day that ended (SPEC 6): kept to build the weekly report.
    public struct DaySummary: Codable, Equatable {
        public var day: String
        public var used: Int
        public var extra: Int
        public var minecraft: Int
        public var requests: Int
        public var approved: Int
        public var denied: Int

        public init(day: String, used: Int = 0, extra: Int = 0, minecraft: Int = 0,
                    requests: Int = 0, approved: Int = 0, denied: Int = 0) {
            self.day = day
            self.used = used
            self.extra = extra
            self.minecraft = minecraft
            self.requests = requests
            self.approved = approved
            self.denied = denied
        }

        /// `minecraft`: Minecraft seconds of that day, from the usage log.
        public static func from(_ ledger: DayLedger, minecraft: Int) -> DaySummary {
            DaySummary(day: ledger.day, used: ledger.used, extra: ledger.extra, minecraft: minecraft,
                       requests: ledger.requests ?? 0, approved: ledger.approved ?? 0,
                       denied: ledger.denied ?? 0)
        }
    }

    public struct History: Codable, Equatable {
        public static let keepDays = 35
        /// Oldest first.
        public var days: [DaySummary]
        /// The day key of the last weekly report sent.
        public var lastReport: String?

        public init(days: [DaySummary] = [], lastReport: String? = nil) {
            self.days = days
            self.lastReport = lastReport
        }

        /// Adds or replaces the summary of that day; keeps the days sorted and at most `keepDays`.
        public mutating func record(_ summary: DaySummary) {
            days.removeAll { $0.day == summary.day }
            days.append(summary)
            days.sort { $0.day < $1.day }
            if days.count > History.keepDays {
                days.removeFirst(days.count - History.keepDays)
            }
        }

        /// The 7 days ending with `today` (oldest first). A day not in the history is
        /// `today` itself when it matches `todaySummary.day`, otherwise an empty summary.
        public func week(ending todaySummary: DaySummary, calendar: Calendar) -> [DaySummary] {
            var result: [DaySummary] = []
            guard let end = History.date(todaySummary.day, calendar: calendar) else { return [todaySummary] }
            for back in (0..<7).reversed() {
                let date = calendar.date(byAdding: .day, value: -back, to: end)!
                let key = DayLedger.dayKey(date, calendar: calendar)
                if key == todaySummary.day {
                    result.append(todaySummary)
                } else {
                    result.append(days.first { $0.day == key } ?? DaySummary(day: key))
                }
            }
            return result
        }

        /// `"2026-11-23"` -> noon of that day in the calendar's time zone.
        public static func date(_ key: String, calendar: Calendar) -> Date? {
            let parts = key.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3 else { return nil }
            return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
        }
    }

## Sources/FamilyTimerCore/Replies.swift

1. `body(to:...)`: the line `case .apps:` becomes `case .apps, .week:` (it still returns `""`).
2. `help`: right after the `/oggi` line, en `"/week - summary of the last 7 days"`, it
   `"/settimana - riepilogo degli ultimi 7 giorni"`.
3. New function, after `usage(...)`:

        /// The weekly report. `days`: 7 summaries, oldest first (`History.week`).
        public static func weekly(child: String, days: [DaySummary], entries: [UsageEntry],
                                  categories: [String: UsageCategory], calendar: Calendar,
                                  _ l: Language) -> String

   Lines, joined with `"\n"`:
   1. `range` = `short(first.day) + "–" + short(last.day)` where `short("2026-11-23")` is
      `"23/11"` (day/month of the key, written as in the key: `"2026-11-03"` gives `"03/11"`).
      en `"📊 \(child), last 7 days (\(range)):"`, it `"📊 \(child), ultimi 7 giorni (\(range)):"`.
   2. `total` = sum of `used`, `average` = `total / days.count`.
      en `"Computer: \(duration(total)) in all, \(duration(average)) a day on average"`,
      it `"Computer: \(duration(total)) in tutto, in media \(duration(average)) al giorno"`.
   3. Only when the sum of `minecraft` is more than 0: `"Minecraft: \(duration(sum))"` (both languages).
   4. Only when the sum of `requests` is more than 0, with `a` = sum of `approved`, `d` = sum of `denied`:
      en `"Time requests: \(r) (\(a) yes, \(d) no)"`, it `"Richieste di tempo: \(r) (\(a) sì, \(d) no)"`.
   5. Only when the sum of `extra` is more than 0:
      en `"Extra time given: \(duration(sum))"`, it `"Tempo extra dato: \(duration(sum))"`.
   6. One line with every day: `"\(weekday) \(duration(used))"` joined with `" · "`, where
      `weekday` comes from `calendar.component(.weekday, from: History.date(day, calendar: calendar)!)`
      (1 = Sunday): en `["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]`,
      it `["dom", "lun", "mar", "mer", "gio", "ven", "sab"]`.
   7. `top = entries.filter { !UsageLog.isSite($0.key) && $0.seconds >= 60 }.prefix(3)`; when
      not empty: en `"Top: "`, it `"In cima: "`, followed by the items joined with `" · "`,
      each `"\(emoji) \(e.name) \(duration(e.seconds))"` with `emoji` = `"🌐"` for
      `UsageLog.isBrowser(e.key)`, otherwise `categoryEmoji(categories[e.key])`.

## Tests/FamilyTimerCoreTests/WeeklyTests.swift (new; its SEARCH section is empty)

`import XCTest`, `@testable import FamilyTimerCore`, `final class WeeklyTests: XCTestCase`.
Copy from `PolicyTests.swift` exactly: `calendar`, `config`, `at`, `reduce`, `state`,
`inGrace`, `inPending`. 2026-11-23 is a Monday.

1. `testCounts`: `let (p, _) = reduce(inGrace(), .askForTime(requestID: "r1"), at(10, 1))`:
   `p.ledger.requests == 1`. `let (a, _) = reduce(p, .answer(requestID: "r1", approved: true, seconds: 300), at(10, 2))`:
   `a.ledger.approved == 1`, `a.ledger.denied == nil`. `let (d, _) = reduce(inPending(), .answer(requestID: "r1", approved: false), at(10, 2))`:
   `d.ledger.denied == 1`. An answer to an unknown id
   `reduce(inPending(), .answer(requestID: "zz", approved: true), at(10, 2)).0.ledger.approved == nil`.
2. `testOldStateDecodes`: decoding
   `Data("{\"day\":\"2026-11-23\",\"used\":5,\"extra\":0,\"lockedByParent\":false}".utf8)` as
   `DayLedger` gives `requests == nil` and `used == 5`.
3. `testParse`: `parseCommand("/settimana") == .success(.week)`, `parseCommand("/week") == .success(.week)`;
   `Replies.help(.it)` contains `"/settimana - riepilogo degli ultimi 7 giorni"`.
4. `testHistory`: `var h = History()`; record `DaySummary(day: "2026-11-20", used: 100)`, then
   `DaySummary(day: "2026-11-18", used: 50)`, then `DaySummary(day: "2026-11-20", used: 200)`:
   `h.days.map(\.day) == ["2026-11-18", "2026-11-20"]` and `h.days[1].used == 200`.
   Then record 40 days `DaySummary(day: String(format: "2026-10-%02d", n))` for n in 1...31 and
   `DaySummary(day: String(format: "2026-09-%02d", n))` for n in 1...9: `h.days.count == 35`,
   `h.days.first?.day == "2026-10-08"`, `h.days.last?.day == "2026-11-20"`.
5. `testWeek`: `let h = History(days: [DaySummary(day: "2026-11-17", used: 3600), DaySummary(day: "2026-11-22", used: 1800, minecraft: 900)])`;
   `let w = h.week(ending: DaySummary(day: "2026-11-23", used: 600), calendar: calendar)`:
   `w.map(\.day) == ["2026-11-17", "2026-11-18", "2026-11-19", "2026-11-20", "2026-11-21", "2026-11-22", "2026-11-23"]`,
   `w.map(\.used) == [3600, 0, 0, 0, 0, 1800, 600]`.
6. `testWeeklyText`: with `w` from test 5 but built from
   `History(days: [DaySummary(day: "2026-11-17", used: 3600, extra: 1800, requests: 2, approved: 1, denied: 1), DaySummary(day: "2026-11-22", used: 1800, minecraft: 900)])`
   and today `DaySummary(day: "2026-11-23", used: 600)`, entries
   `[UsageEntry(key: "app:com.mojang.minecraft", name: "Minecraft", seconds: 900), UsageEntry(key: "site:youtube.com", name: "youtube.com", seconds: 800), UsageEntry(key: "app:com.google.Chrome", name: "Chrome", seconds: 700)]`,
   categories `["app:com.mojang.minecraft": .games]`:
   `Replies.weekly(child: "Art", days: w, entries: entries, categories: categories, calendar: calendar, .it)` equals

        "📊 Art, ultimi 7 giorni (17/11–23/11):\nComputer: 1h 40m in tutto, in media 14m al giorno\nMinecraft: 15m\nRichieste di tempo: 2 (1 sì, 1 no)\nTempo extra dato: 30m\nmar 1h 00m · mer 0m · gio 0m · ven 0m · sab 0m · dom 30m · lun 10m\nIn cima: 🎮 Minecraft 15m · 🌐 Chrome 11m"

   And with `days` = 7 empty summaries from `History().week(ending: DaySummary(day: "2026-11-23"), calendar: calendar)`,
   entries `[]`, `.en`: the text equals

        "📊 Art, last 7 days (17/11–23/11):\nComputer: 0m in all, 0m a day on average\nTue 0m · Wed 0m · Thu 0m · Fri 0m · Sat 0m · Sun 0m · Mon 0m"
