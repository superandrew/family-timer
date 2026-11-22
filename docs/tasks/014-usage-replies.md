+++
id = "014"
title = "/app and /oggi commands, usage replies, category buttons"
edit = ["Sources/FamilyTimerCore/Commands.swift", "Sources/FamilyTimerCore/Policy.swift", "Sources/FamilyTimerCore/Replies.swift", "Tests/FamilyTimerCoreTests/CommandsTests.swift", "Tests/FamilyTimerCoreTests/RepliesTests.swift", "Tests/FamilyTimerCoreTests/PolicyTests.swift"]
read = ["Sources/FamilyTimerCore/Usage.swift"]
checks = ["swift build", "swift test --filter PolicyTests", "swift test --filter CommandsTests", "swift test --filter RepliesTests", "swift test", "git --no-pager diff --check HEAD"]
commit = "feat(core): /app and /oggi commands, usage replies, category buttons"
edit_format = "diff"
+++

# 014 - /app and /oggi, usage replies

All files exist. `UsageLog`, `UsageEntry` and `UsageCategory` exist in `Usage.swift` (task 013):
read it, do not edit it. Change only what is listed here.

## Sources/FamilyTimerCore/Commands.swift

1. Add `case apps(days: Int)` to `enum Command`, after `help`.
2. In `parseCommand`, add before `case "/help", "/start":`

        case "/app", "/apps":
            return .success(.apps(days: 7))
        case "/oggi", "/today":
            return .success(.apps(days: 1))

`parseAddressedCommand` needs no change: `/app bea` already gives target `"bea"`.

## Sources/FamilyTimerCore/Policy.swift

1. In `reduce`, `case let .command(command):`, change `case .status, .help:` to
   `case .status, .help, .apps:` (they change nothing).
2. In `reduce`, `case let .tick(seconds, active):`, inner `case .locked:`: add as its first
   statement (time can come back without a command, for example when the daily limit in the
   config is raised):

        if !s.ledger.lockedByParent
            && (s.ledger.remaining(budget: budget) > 0 || s.ledger.inStudio(at: now)) {
            reopen(&s, now: now, budget: budget, actions: &actions)
            break
        }

   The rest of `case .locked:` (the logout check) stays as it is, after it.

## Sources/FamilyTimerCore/Replies.swift

1. In `body(to:after:now:config:calendar:)` add a case (the daemon answers `/app` with
   `usage`, never with `body`):

        case .apps:
            return ""

2. In `help`, add two lines after the `/unlock` line, in both languages:
   English `/app - apps and sites of the last 7 days` and `/oggi - apps and sites of today`;
   Italian `/app - app e siti degli ultimi 7 giorni` and `/oggi - app e siti di oggi`.
   If a test compares the whole help text, update its expected text the same way.

3. Add these functions at the end of `enum Replies`, using `t(l, en, it)` and `duration(_:)`:

        /// Emoji of a category; nil (not classified yet) is "❓".
        public static func categoryEmoji(_ c: UsageCategory?) -> String
            games "🎮", study "📚", video "📺", other "▫️", nil "❓"

        /// Button text: emoji, a space, the name.
        public static func categoryLabel(_ c: UsageCategory, _ l: Language) -> String
            games: "🎮 games" / "🎮 giochi"
            study: "📚 study" / "📚 studio"
            video: "📺 video" / "📺 video"
            other: "▫️ other" / "▫️ altro"

        public static func usage(_ entries: [UsageEntry], categories: [String: UsageCategory],
                                 child: String, days: Int, limit: Int, _ l: Language) -> String

        public static func classifyPrompt(name: String, seconds: Int, _ l: Language) -> String
            "What is “\(name)” (\(duration(seconds)))?" / "Che cos'è «\(name)» (\(duration(seconds)))?"

        public static func classified(name: String, category: UsageCategory, by: String,
                                      _ l: Language) -> String
            "“\(name)”: \(categoryLabel(category, l)) (\(by))" / "«\(name)»: \(categoryLabel(category, l)) (\(by))"

   `usage` builds lines and joins them with `"\n"`:
   - First line: when `days == 1`, `"\(child), today:"` / `"\(child), oggi:"`; otherwise
     `"\(child), last \(days) days:"` / `"\(child), ultimi \(days) giorni:"`.
   - If `entries` is empty, the second and last line is `"No data yet."` / `"Ancora nessun dato."`.
   - Otherwise: `apps` = the entries whose key is not a site (`UsageLog.isSite`), first `limit`
     of them; `sites` = the site entries, first `limit`. Keep their order.
   - If `apps` is not empty: a line `"Apps:"` / `"App:"`, then one line per entry:
     `"\(categoryEmoji(categories[e.key])) \(e.name) \(duration(e.seconds))"`.
   - If `sites` is not empty: a line `"Sites:"` / `"Siti:"`, then the same kind of line per entry.

## Tests/FamilyTimerCoreTests/CommandsTests.swift

Keep every test. Add `testAppsCommands`: `parseCommand("/app")` is `.success(.apps(days: 7))`,
`parseCommand("/APPS")` too, `parseCommand("/oggi")` and `parseCommand("/today@bot")` are
`.success(.apps(days: 1))`; `parseAddressedCommand("/app bea")` gives `.success(.apps(days: 7))`
and target `"bea"`.

## Tests/FamilyTimerCoreTests/RepliesTests.swift

Keep every test. Add `testUsage`:

    let entries = [UsageEntry(key: "app:com.mojang.minecraft", name: "Minecraft", seconds: 15000),
                   UsageEntry(key: "site:youtube.com", name: "youtube.com", seconds: 4200),
                   UsageEntry(key: "app:com.apple.Safari", name: "Safari", seconds: 4500)]
    let categories: [String: UsageCategory] = ["app:com.mojang.minecraft": .games]

- `Replies.usage(entries, categories: categories, child: "arthur", days: 7, limit: 10, .it)`
  equals `"arthur, ultimi 7 giorni:\nApp:\n🎮 Minecraft 4h 10m\n❓ Safari 1h 15m\nSiti:\n❓ youtube.com 1h 10m"`.
- With `limit: 1` and `.en`: `"arthur, last 7 days:\nApps:\n🎮 Minecraft 4h 10m\nSites:\n❓ youtube.com 1h 10m"`.
- `Replies.usage([], categories: [:], child: "arthur", days: 1, limit: 10, .it)` equals
  `"arthur, oggi:\nAncora nessun dato."`.
- `Replies.classifyPrompt(name: "Minecraft", seconds: 600, .it) == "Che cos'è «Minecraft» (10m)?"`.
- `Replies.classified(name: "Minecraft", category: .games, by: "Andrea", .it) == "«Minecraft»: 🎮 giochi (Andrea)"`.
- `Replies.categoryEmoji(nil) == "❓"` and `Replies.categoryLabel(.study, .en) == "📚 study"`.

Check the durations against `Replies.duration` before writing them: 15000 s is 4h 10m,
4500 s is 1h 15m, 4200 s is 1h 10m, 600 s is 10m.

## Tests/FamilyTimerCoreTests/PolicyTests.swift

Keep every test. Add `testLockedReopensWhenTimeComesBack`:

- `reduce(state(used: 3600, phase: .locked), .tick(seconds: 15, active: true), at(10, 0))`
  stays `.locked` with actions `[]` (the default `config` gives 3600 s on Monday).
- The same with a copy of `config` whose `weekdayLimit = 4000`: phase `.open`, actions
  `[.unlock]`, and `used` is still 3600 (a locked tick does not count).
- With `weekdayLimit = 4000` and a state whose `ledger.lockedByParent = true` (and
  `phase: .locked`): stays `.locked`, actions `[]`.
