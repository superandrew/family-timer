+++
id = "021"
title = "Menu bar: Minecraft in the title, time and usage lines in the menu"
edit = ["Sources/FamilyTimerCore/AgentTexts.swift", "Sources/FamilyTimerCore/AgentProtocol.swift", "Tests/FamilyTimerCoreTests/MenuTests.swift"]
read = ["Sources/FamilyTimerCore/Replies.swift", "Sources/FamilyTimerCore/Usage.swift", "Sources/FamilyTimerCore/DayLedger.swift", "Sources/FamilyTimerCore/Policy.swift", "Tests/FamilyTimerCoreTests/BlockingTests.swift"]
checks = ["test -s Tests/FamilyTimerCoreTests/MenuTests.swift", "swift build", "swift test --filter MenuTests", "swift test", "git add -N -- Tests/FamilyTimerCoreTests/MenuTests.swift && git --no-pager diff --check HEAD"]
commit = "feat(core): menu bar shows Minecraft time; menu lines with time, Minecraft and today's apps"
edit_format = "diff"
+++

# 021 - Menu bar: time left, Minecraft left, today's apps

The child asked to see in the menu bar how much computer time and how much Minecraft time is
left, and a few statistics. The daemon computes the lines (it has the ledger and the usage
log) and sends them in the `state` message; the agent only shows them. This card writes the
pure parts. Existing tests must keep passing without changes.

## Sources/FamilyTimerCore/AgentTexts.swift

1. `menuTitle` gets a new LAST parameter with a default, so existing calls still compile:

        public static func menuTitle(remaining: Int, phase: Phase, graceRemaining: Int?, _ l: Language,
                                     minecraftRemaining: Int? = nil) -> String

   Only in the `.open` case, when `minecraftRemaining` is not nil, append
   `" ⛏ " + Replies.duration(minecraftRemaining! + 59)` to the existing text. The other
   cases do not change. (The agent passes it only while Minecraft is running.)

2. New function, after `menuTitle`:

        /// Lines of the menu bar menu: time left, Minecraft left, study time, today's top apps.
        public static func menuLines(_ state: PolicyState, now: Date, config: Config, calendar: Calendar,
                                     minecraftPlayed: Int?, today: [UsageEntry],
                                     categories: [String: UsageCategory]) -> [String]

   With `l = config.language`, `ledger = state.ledger`,
   `budget = DayLedger.budget(for: now, config: config, calendar: calendar)`, lines in order:
   1. Always:
      `left = Replies.duration(ledger.remaining(budget: budget) + 59)`,
      `total = Replies.duration(budget + ledger.extra)`,
      `used = Replies.duration(ledger.used)`;
      en `"Computer: \(left) left (used \(used) of \(total))"`,
      it `"Computer: restano \(left) (usati \(used) su \(total))"`.
   2. When `minecraftPlayed` is not nil and
      `Policy.minecraftRemaining(state, played: minecraftPlayed!, now: now, config: config, calendar: calendar)`
      is not nil (call it `mcLeft`):
      `mcTotal = DayLedger.minecraftBudget(for: now, config: config, calendar: calendar) + (ledger.minecraftExtra ?? 0)`;
      en `"Minecraft: \(Replies.duration(mcLeft + 59)) left (played \(Replies.duration(played)) of \(Replies.duration(mcTotal)))"`,
      it `"Minecraft: restano \(Replies.duration(mcLeft + 59)) (giocati \(Replies.duration(played)) su \(Replies.duration(mcTotal)))"`.
      Careful: when `mcLeft` is 0 the text is `"0m"`: write `mcLeft == 0 ? "0m" : Replies.duration(mcLeft + 59)`.
      Do the same for `left` in line 1: `ledger.remaining(budget: budget) == 0 ? "0m" : Replies.duration(... + 59)`.
   3. When `ledger.inStudio(at: now)` and `ledger.studioUntil` is not nil:
      `c = Replies.clock(until, calendar: calendar)`; en `"Study time until \(c)"`, it `"Studio fino alle \(c)"`.
   4. `apps = today.filter { !UsageLog.isSite($0.key) && $0.seconds >= 60 }.prefix(3)`.
      When not empty: a header line en `"Today:"`, it `"Oggi:"`, then for each entry
      `"\(emoji) \(e.name) \(Replies.duration(e.seconds))"` where `emoji` is `"🌐"` when
      `UsageLog.isBrowser(e.key)`, otherwise `Replies.categoryEmoji(categories[e.key])`.

## Sources/FamilyTimerCore/AgentProtocol.swift

`DaemonMessage`: a new optional property, documented `/// \`state\`: lines of the menu.`,
`public var menu: [String]?`, with an init parameter `menu: [String]? = nil` added at the END
of the init parameter list (after `reason`), assigned in the init. Nothing else changes.

## Tests/FamilyTimerCoreTests/MenuTests.swift (new; its SEARCH section is empty)

`import XCTest`, `@testable import FamilyTimerCore`, `final class MenuTests: XCTestCase`.
Copy the `calendar` property and the `at` helper from `BlockingTests.swift`. Config:

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

Tests (2026-11-23 is a Monday):

1. `testLines`: `PolicyState(ledger: DayLedger(day: "2026-11-23", used: 600))`,
   `AgentTexts.menuLines(s, now: at(10, 0), config: config, calendar: calendar, minecraftPlayed: 1200, today: today, categories: categories)`
   equals exactly

        ["Computer: restano 50m (usati 10m su 1h 00m)",
         "Minecraft: restano 25m (giocati 20m su 45m)",
         "Oggi:",
         "🎮 Minecraft 20m",
         "🌐 Chrome 5m",
         "💻 Terminal 2m"]

2. `testExtrasAndNoMinecraft`: `DayLedger(day: "2026-11-23", used: 600, extra: 1800)` with
   `ledger.minecraftExtra = 900` set on the ledger variable before building the state;
   `minecraftPlayed: 3600`, `today: []`: equals exactly

        ["Computer: restano 1h 20m (usati 10m su 1h 30m)",
         "Minecraft: restano 0m (giocati 1h 00m su 1h 00m)"]

   And with `minecraftPlayed: nil`, same ledger: equals `["Computer: restano 1h 20m (usati 10m su 1h 30m)"]`.

3. `testStudio`: `DayLedger(day: "2026-11-23", used: 600, studioUntil: at(11, 30))`,
   `minecraftPlayed: 0`, `today: []`, now `at(10, 0)`: equals exactly

        ["Computer: restano 50m (usati 10m su 1h 00m)",
         "Minecraft: restano 0m (giocati 0m su 45m)",
         "Studio fino alle 11:30"]

4. `testTitle`:
   `AgentTexts.menuTitle(remaining: 1500, phase: .open, graceRemaining: nil, .it) == "⏱ 25m"`;
   `AgentTexts.menuTitle(remaining: 1500, phase: .open, graceRemaining: nil, .it, minecraftRemaining: 600) == "⏱ 25m ⛏ 10m"`;
   `AgentTexts.menuTitle(remaining: 0, phase: .locked, graceRemaining: nil, .it, minecraftRemaining: 600) == "⏱ bloccato"`.

5. `testWire`: `DaemonMessage(type: .state, remaining: 60, menu: ["a", "b"])` encoded with
   `Wire.encode` and decoded with `JSONDecoder` (drop the trailing newline byte first) is equal
   to the original, and the encoded string contains `"\"menu\":[\"a\",\"b\"]"`.
