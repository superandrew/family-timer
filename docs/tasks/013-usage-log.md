+++
id = "013"
title = "UsageLog: seconds per app and per site, per day"
edit = ["Sources/FamilyTimerCore/Usage.swift", "Tests/FamilyTimerCoreTests/UsageTests.swift"]
read = ["Package.swift", "Tests/FamilyTimerCoreTests/VersionTests.swift"]
checks = ["test -s Sources/FamilyTimerCore/Usage.swift && test -s Tests/FamilyTimerCoreTests/UsageTests.swift", "swift build", "swift test --filter UsageTests", "swift test", "git add -N -- Sources/FamilyTimerCore/Usage.swift Tests/FamilyTimerCoreTests/UsageTests.swift && git --no-pager diff --check HEAD"]
commit = "feat(core): UsageLog counts seconds per app and per site, per day"
edit_format = "whole"
+++

# 013 - UsageLog

Both files are new. Write them whole. Pure logic: no clock, the day is a `"yyyy-MM-dd"`
string parameter.

The agent tells the daemon which app is in front and, for a browser, the address of the
page. Every 15 s of active use the daemon adds 15 s to that app and to that site. The parents
then see where the time goes and put each app or site in a category.

## Sources/FamilyTimerCore/Usage.swift

    import Foundation

    public enum UsageCategory: String, Codable, CaseIterable, Equatable {
        case games
        case study
        case video
        case other
    }

    /// What the agent reports: the frontmost app and, for a browser, the page.
    public struct Frontmost: Codable, Equatable {
        public var bundleID: String
        public var name: String
        public var url: String?
        public var title: String?

        public init(bundleID: String, name: String, url: String? = nil, title: String? = nil)
    }

    public struct UsageEntry: Equatable {
        public var key: String
        public var name: String
        public var seconds: Int

        public init(key: String, name: String, seconds: Int)
    }

    public struct DayUsage: Codable, Equatable {
        public var day: String
        public var seconds: [String: Int]

        public init(day: String, seconds: [String: Int] = [:])
    }

    public struct UsageLog: Codable, Equatable {
        public static let keepDays = 35

        /// Oldest first, at most `keepDays`.
        public var days: [DayUsage]
        /// Key -> name to show (app name, or the site's host).
        public var names: [String: String]
        /// Key -> category chosen by a parent.
        public var categories: [String: UsageCategory]

        public init()   // all empty

        public static func appKey(_ bundleID: String) -> String
        public static func siteKey(url: String) -> String?
        public static func isSite(_ key: String) -> Bool
        public mutating func add(_ frontmost: Frontmost, seconds: Int, day: String)
        public func entries(from firstDay: String, to lastDay: String) -> [UsageEntry]
        public func total(for key: String) -> Int
    }

Rules:

- `appKey(b)` is `"app:" + b`.
- `siteKey(url:)`:
  1. Trim spaces and newlines. If the text does not contain `"://"`, put `"https://"` in front
     (browsers often show the address without it).
  2. `URL(string:)`; return nil if it is nil, if its `scheme` lowercased is not `"http"` or
     `"https"`, or if its `host` is nil or empty.
  3. Lowercase the host; if it starts with `"www."`, drop those 4 characters.
  4. Return `"site:" + host`.
- `isSite(key)` is `key.hasPrefix("site:")`.
- `add(frontmost, seconds:, day:)`: does nothing when `seconds <= 0`. Otherwise:
  1. Find the `DayUsage` with that `day`. If there is none, append `DayUsage(day: day)` and
     sort `days` by `day` (strings compare correctly).
  2. Add `seconds` to the app key `appKey(frontmost.bundleID)` of that day, and set
     `names[appKey] = frontmost.name`.
  3. If `frontmost.url` is not nil and `siteKey(url:)` gives a key, add `seconds` to that key
     too and set `names[siteKey]` to the host (the key without `"site:"`).
  4. While `days.count > UsageLog.keepDays`, remove the first element.
- `entries(from:to:)`: sum the seconds of every key over the days with
  `firstDay <= day && day <= lastDay`. One `UsageEntry` per key, `name = names[key] ?? key`.
  Sorted by `seconds` descending, then by `key` ascending.
- `total(for:)`: the seconds of that key over all the days kept.

## Tests/FamilyTimerCoreTests/UsageTests.swift

`final class UsageTests: XCTestCase`, like `VersionTests.swift`. One test method per case:

1. `siteKey(url:)`:
   `"https://www.YouTube.com/watch?v=1"` -> `"site:youtube.com"`;
   `"classroom.google.com/c/123"` -> `"site:classroom.google.com"`;
   `"  http://poki.com  "` -> `"site:poki.com"`;
   `"file:///Users/a/x.html"` -> nil; `"about:blank"` -> nil; `"minecraft mods"` -> nil;
   `""` -> nil.
2. `appKey("com.mojang.minecraft") == "app:com.mojang.minecraft"`, `isSite("site:a.com")`
   is true, `isSite("app:a")` is false.
3. Add `Frontmost(bundleID: "com.apple.Safari", name: "Safari", url: "https://www.youtube.com/x")`
   for 15 s on `"2026-11-22"` twice, and `Frontmost(bundleID: "com.mojang.minecraft", name: "Minecraft")`
   for 15 s once. `entries(from: "2026-11-22", to: "2026-11-22")` equals
   `[UsageEntry(key: "app:com.apple.Safari", name: "Safari", seconds: 30),
     UsageEntry(key: "site:youtube.com", name: "youtube.com", seconds: 30),
     UsageEntry(key: "app:com.mojang.minecraft", name: "Minecraft", seconds: 15)]`.
4. Days: add Minecraft 15 s on `"2026-11-21"`, 30 s on `"2026-11-22"`, 45 s on
   `"2026-11-20"` (out of order). `days.map(\.day) == ["2026-11-20", "2026-11-21", "2026-11-22"]`;
   `entries(from: "2026-11-21", to: "2026-11-22")` has one entry with 45 s;
   `total(for: "app:com.mojang.minecraft") == 90`.
5. Keep days: add 15 s on each of 40 days, `"2026-10-01"` to `"2026-11-09"` (build the
   strings with `String(format:)`; October has 31 days). Then `days.count == 35` and
   `days.first?.day == "2026-10-06"`.
6. `seconds: 0` changes nothing: the log equals `UsageLog()`.
7. A url that gives no site (`"about:blank"`) counts only the app: one entry.
8. JSON round trip: a log with one day, a name and
   `categories["app:com.mojang.minecraft"] = .games` encodes and decodes to an equal value.
