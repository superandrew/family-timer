+++
id = "003"
title = "Day ledger"
edit = ["Sources/FamilyTimerCore/DayLedger.swift", "Tests/FamilyTimerCoreTests/DayLedgerTests.swift"]
read = ["Package.swift", "Sources/FamilyTimerCore/Config.swift", "Tests/FamilyTimerCoreTests/VersionTests.swift"]
checks = ["test -s Sources/FamilyTimerCore/DayLedger.swift && test -s Tests/FamilyTimerCoreTests/DayLedgerTests.swift", "swift build", "swift test --filter DayLedgerTests", "swift test", "git add -N -- Sources/FamilyTimerCore/DayLedger.swift Tests/FamilyTimerCoreTests/DayLedgerTests.swift && git --no-pager diff --check HEAD"]
commit = "feat(core): day ledger with budget, extra time and studio windows"
edit_format = "whole"
+++

# 003 - Day ledger

Both files are new. Write them whole. `Config` exists already (task 001), read it, do not
edit it.

## Sources/FamilyTimerCore/DayLedger.swift

    import Foundation

    public struct DayLedger: Codable, Equatable {
        public var day: String
        public var used: Int
        public var extra: Int
        public var studioUntil: Date?
        public var lockedByParent: Bool

        public init(day: String, used: Int = 0, extra: Int = 0,
                    studioUntil: Date? = nil, lockedByParent: Bool = false)

        public static func dayKey(_ date: Date, calendar: Calendar) -> String
        public static func budget(for date: Date, config: Config, calendar: Calendar) -> Int
        public static func fresh(for date: Date, calendar: Calendar) -> DayLedger

        public func rolled(to date: Date, calendar: Calendar) -> DayLedger
        public func inStudio(at now: Date) -> Bool
        public func remaining(budget: Int) -> Int
        public mutating func tick(seconds: Int, active: Bool, now: Date)
        public mutating func grantExtra(seconds: Int)
        public mutating func startStudio(seconds: Int, now: Date)
    }

- `dayKey`: `calendar.dateComponents([.year, .month, .day], from: date)`, formatted with
  `String(format: "%04d-%02d-%02d", year, month, day)`. No `DateFormatter`.
- `budget`: `config.weekendLimit` when `calendar.isDateInWeekend(date)`, else
  `config.weekdayLimit`.
- `fresh`: `DayLedger(day: dayKey(date, calendar: calendar))`.
- `rolled`: `self` when `dayKey(date, calendar:)` equals `day`, else `fresh(for:calendar:)`.
- `inStudio`: true only when `studioUntil` is not nil and `now < studioUntil`.
- `remaining`: `max(0, budget + extra - used)`.
- `tick`: adds `seconds` to `used` only when `active` is true and `inStudio(at: now)` is
  false.
- `grantExtra`: `extra += seconds`.
- `startStudio`: `studioUntil = now.addingTimeInterval(TimeInterval(seconds))`.

## Tests/FamilyTimerCoreTests/DayLedgerTests.swift

`final class DayLedgerTests: XCTestCase`, like `VersionTests.swift`. Add these helpers to the
class, exactly:

    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Rome")!
        return c
    }()

    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

Facts: 2026-11-21 is a Saturday, 2026-11-22 a Sunday, 2026-11-23 a Monday.
`let config = Config(childUser: "a", weekdayLimit: 3600, weekendLimit: 7200)`.

One test method per case:

1. `dayKey(date(2026, 11, 23, 10, 0))` is `"2026-11-23"`; `dayKey(date(2026, 11, 23, 23, 59))`
   is `"2026-11-23"`; `dayKey(date(2026, 11, 24, 0, 0))` is `"2026-11-24"`.
2. `budget`: Monday 23 at 10:00 is `3600`; Saturday 21 at 10:00 is `7200`; Sunday 22 at
   10:00 is `7200`.
3. `fresh(for: date(2026, 11, 23, 10, 0))` equals `DayLedger(day: "2026-11-23")`.
4. `tick`: from `fresh` on Monday 10:00, `tick(seconds: 15, active: true, now:)` twice
   gives `used == 30`; then `tick(seconds: 15, active: false, now:)` leaves `30`.
5. Studio: on Monday, `startStudio(seconds: 7200, now: date(2026, 11, 23, 10, 0))`;
   `studioUntil == date(2026, 11, 23, 12, 0)`; `inStudio(at: date(2026, 11, 23, 11, 59))`
   true; `inStudio(at: date(2026, 11, 23, 12, 0))` false;
   `tick(seconds: 15, active: true, now: date(2026, 11, 23, 11, 0))` leaves `used == 0`;
   `tick(seconds: 15, active: true, now: date(2026, 11, 23, 12, 1))` gives `used == 15`.
6. `remaining`: `DayLedger(day: "x", used: 3000).remaining(budget: 3600)` is `600`;
   `DayLedger(day: "x", used: 4000).remaining(budget: 3600)` is `0`;
   `DayLedger(day: "x", used: 4000, extra: 1800).remaining(budget: 3600)` is `1400`.
7. `grantExtra(seconds: 1800)` twice gives `extra == 3600`.
8. `rolled`: `DayLedger(day: "2026-11-23", used: 500, lockedByParent: true)` rolled to
   `date(2026, 11, 23, 22, 0)` is unchanged; rolled to `date(2026, 11, 24, 0, 1)` equals
   `DayLedger(day: "2026-11-24")`.
9. Codable round trip: a ledger with `used: 10, extra: 20,
   studioUntil: date(2026, 11, 23, 12, 0), lockedByParent: true`, encoded with
   `JSONEncoder()` and decoded with `JSONDecoder()`, is equal to the original.
