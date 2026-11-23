+++
id = "019"
title = "Minecraft limit: config, extra minutes, /minecraft command, remaining"
edit = ["Sources/FamilyTimerCore/Config.swift", "Sources/FamilyTimerCore/DayLedger.swift", "Sources/FamilyTimerCore/Commands.swift", "Sources/FamilyTimerCore/Policy.swift", "Sources/FamilyTimerCore/Replies.swift", "Tests/FamilyTimerCoreTests/MinecraftTests.swift"]
read = ["Tests/FamilyTimerCoreTests/PolicyTests.swift"]
checks = ["test -s Tests/FamilyTimerCoreTests/MinecraftTests.swift", "swift build", "swift test --filter MinecraftTests", "swift test", "git add -N -- Tests/FamilyTimerCoreTests/MinecraftTests.swift && git --no-pager diff --check HEAD"]
commit = "feat(core): Minecraft limit (config, /minecraft extra, remaining)"
edit_format = "diff"
+++

# 019 - Minecraft limit, the logic

A daily limit for Minecraft alone, inside the daily limit of the Mac: 45 minutes on weekdays,
60 at the weekend. The daemon counts the Minecraft seconds of today (from the usage log) and
asks the core how much is left. Parents give more Minecraft time with `/minecraft 15m`;
`/extra` does not change Minecraft. During a study window Minecraft has 0 left.

Only the logic and the tests. Texts come in a later card.

## Sources/FamilyTimerCore/Config.swift

Two new properties, after `weekendLimit`:

    /// Seconds of Minecraft per weekday; 0 = no Minecraft limit.
    public var minecraftLimit: Int
    /// Seconds of Minecraft per weekend day; 0 = no Minecraft limit.
    public var weekendMinecraftLimit: Int

`init`: two parameters with default `0`, right after `weekendLimit`. `parse`: keys
`MINECRAFT_LIMIT` and `WEEKEND_MINECRAFT_LIMIT`, integers `>= 0` (0 allowed), otherwise
`ConfigError.invalidNumber(key:value:)`. When `MINECRAFT_LIMIT` is set and
`WEEKEND_MINECRAFT_LIMIT` is not, the weekend value is the same as `MINECRAFT_LIMIT`.
Both missing: both 0.

## Sources/FamilyTimerCore/DayLedger.swift

- New property `public var minecraftExtra: Int?` (optional, so old state files still
  decode), init parameter `minecraftExtra: Int? = nil` at the end.
- `public mutating func grantMinecraftExtra(seconds: Int)`: `minecraftExtra = (minecraftExtra ?? 0) + seconds`.
- `public static func minecraftBudget(for date: Date, config: Config, calendar: Calendar) -> Int`:
  like `budget`, with `minecraftLimit` / `weekendMinecraftLimit`.

`fresh` and `rolled` do not change: a new day starts with `minecraftExtra == nil`.

## Sources/FamilyTimerCore/Commands.swift

- `Command`: new case `minecraft(seconds: Int)`.
- `parseCommand`: `/minecraft` and `/mc` take a duration exactly like `/extra` (same errors:
  `missingDuration(word)`, `invalidDuration(text)`), and return `.minecraft(seconds:)`.
- `parseAddressedCommand`: treat `/minecraft` and `/mc` like `/extra` and `/studio` (the
  name may come before or after the duration).

## Sources/FamilyTimerCore/Policy.swift

- In `reduce`, `.command(.minecraft(seconds))`: `s.ledger.grantMinecraftExtra(seconds: seconds)`.
  No other change, no actions. The phase does not change.
- New function:

      /// Seconds of Minecraft left today; nil when there is no Minecraft limit.
      /// `played`: Minecraft seconds already counted today.
      public static func minecraftRemaining(_ s: PolicyState, played: Int, now: Date,
                                            config: Config, calendar: Calendar) -> Int?

  `let budget = DayLedger.minecraftBudget(for: now, config: config, calendar: calendar)`.
  `budget == 0` -> nil. `s.ledger.inStudio(at: now)` -> 0. Otherwise
  `max(0, budget + (s.ledger.minecraftExtra ?? 0) - played)`.

## Sources/FamilyTimerCore/Replies.swift

`Command` has a new case, so the `switch command` in `body(to:...)` must handle it. For
now return `""` for `.minecraft`, like `.apps`. Change nothing else in this file.

## Tests/FamilyTimerCoreTests/MinecraftTests.swift

New file, `final class MinecraftTests: XCTestCase`. Copy the `calendar` (Europe/Rome), `at`
and `config` helpers from `PolicyTests.swift`, with `minecraftLimit: 2700,
weekendMinecraftLimit: 3600` in `config`. 2026-11-23 is a Monday; 2026-11-28 a Saturday.

1. Config: `Config.parse("CHILD_USER=a\nMINECRAFT_LIMIT=2700")` gives 2700 and 2700;
   with `WEEKEND_MINECRAFT_LIMIT=3600` too, 2700 and 3600; without both, 0 and 0;
   `MINECRAFT_LIMIT=abc` throws `.invalidNumber(key: "MINECRAFT_LIMIT", value: "abc")`;
   `MINECRAFT_LIMIT=0` gives 0.
2. Commands: `parseCommand("/minecraft 15m") == .success(.minecraft(seconds: 900))`,
   `parseCommand("/mc 30") == .success(.minecraft(seconds: 1800))`,
   `parseCommand("/minecraft") == .failure(.missingDuration("/minecraft"))`;
   `parseAddressedCommand("/minecraft 15m art")` gives `.success(.minecraft(seconds: 900))`
   and target `"art"`; `parseAddressedCommand("/mc art 15")` the same.
3. Remaining on a weekday: a fresh `PolicyState(ledger: DayLedger(day: "2026-11-23"))`,
   `played: 600` at `at(9, 0)` -> 2100; `played: 3000` -> 0.
4. Weekend: day 28, `played: 600` at `at(9, 0, day: 28)` -> 3000 (use a ledger with
   `day: "2026-11-28"`).
5. No limit: a config without Minecraft limits -> nil.
6. Extra: `reduce` the fresh state with `.command(.minecraft(seconds: 900))` at `at(9, 0)`:
   actions `[]`, phase `.open`, `ledger.minecraftExtra == 900`, `ledger.extra == 0`;
   remaining with `played: 3000` -> 600. A second `/minecraft 900` gives `minecraftExtra == 1800`.
7. `/extra` does not change Minecraft: after `.command(.extra(seconds: 1800))`,
   `minecraftRemaining` with `played: 600` is still 2100.
8. Studio: after `.command(.studio(seconds: 3600))` at `at(9, 0)`, remaining at
   `at(9, 30)` with `played: 0` -> 0, and at `at(10, 30)` -> 2700.
9. A `DayLedger` JSON without `minecraftExtra` (encode `DayLedger(day: "2026-11-23")`,
   check it decodes back) decodes with `minecraftExtra == nil`.
