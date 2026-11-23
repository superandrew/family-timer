+++
id = "020"
title = "Which app to close (Minecraft over, study time), protocol fields and texts"
edit = ["Sources/FamilyTimerCore/Blocking.swift", "Sources/FamilyTimerCore/AgentProtocol.swift", "Sources/FamilyTimerCore/AgentTexts.swift", "Sources/FamilyTimerCore/Replies.swift", "Tests/FamilyTimerCoreTests/BlockingTests.swift"]
read = ["Tests/FamilyTimerCoreTests/RepliesTests.swift", "Tests/FamilyTimerCoreTests/MinecraftTests.swift", "Sources/FamilyTimerCore/Usage.swift"]
checks = ["test -s Sources/FamilyTimerCore/Blocking.swift && test -s Tests/FamilyTimerCoreTests/BlockingTests.swift", "swift build", "swift test --filter BlockingTests", "swift test", "git add -N -- Sources/FamilyTimerCore/Blocking.swift Tests/FamilyTimerCoreTests/BlockingTests.swift && git --no-pager diff --check HEAD"]
commit = "feat(core): which app to close (Minecraft over, study time), texts and protocol fields"
edit_format = "diff"
+++

# 020 - Closing apps: the decision, the protocol, the texts

Card 019 added the Minecraft limit. Now the daemon must decide which app to close:
Minecraft when its time is over, and during a study window (`/studio`) Minecraft and every
app classified as games or coding. Browsers and sites are never closed (sites cannot be
blocked without network filtering). The agent closes the app and shows a notice.

## Sources/FamilyTimerCore/Blocking.swift (new)

    import Foundation

    /// Why an app is closed.
    public enum BlockReason: String, Codable, Equatable {
        case minecraftOver = "minecraft_over"
        case studio
    }

    public enum Blocking {
        /// Usage key of Minecraft (the agent reports Minecraft Java under this bundle id).
        public static let minecraftKey = "app:com.mojang.minecraft"
        /// Categories closed during a study window.
        public static let studioBlocked: Set<UsageCategory> = [.games, .coding]

        public static func reason(appKey: String, category: UsageCategory?,
                                  minecraftRemaining: Int?, inStudio: Bool) -> BlockReason?
    }

`reason`, in this order:
1. `UsageLog.isSite(appKey)` or `UsageLog.isBrowser(appKey)`: nil.
2. `inStudio` and (`appKey == minecraftKey` or `category` is in `studioBlocked`): `.studio`.
3. `appKey == minecraftKey` and `minecraftRemaining == 0`: `.minecraftOver`.
4. Otherwise nil.

## Sources/FamilyTimerCore/AgentProtocol.swift

- `DaemonMessageType`: new case `close` (raw value `"close"`).
- `DaemonMessage`: three new optional properties, with init parameters defaulting to nil,
  added at the END of the init parameter list:
  - `minecraftRemaining: Int?` (`state`: Minecraft seconds left today, nil = no limit)
  - `app: String?` (`close`: usage key of the app to close, like `"app:com.mojang.minecraft"`)
  - `reason: BlockReason?` (`close`)
- `from(_:)` does not change.

## Sources/FamilyTimerCore/AgentTexts.swift

Add, using `t(l, en, it)` like the other texts:

    public static func minecraftWarning(minutes: Int, _ l: Language) -> String
    public static func closed(app: String, reason: BlockReason, _ l: Language) -> String

- `minecraftWarning`: minutes == 1: en `"Minecraft: 1 minute left today. Save your world."`,
  it `"Minecraft: manca 1 minuto. Salva il mondo."`; otherwise en
  `"Minecraft: \(minutes) minutes left today."`, it `"Minecraft: mancano \(minutes) minuti per oggi."`
- `closed`, `.minecraftOver`: en `"Minecraft time is over for today. The game is closing."`,
  it `"Il tempo di Minecraft per oggi è finito. Il gioco si chiude."`; `.studio`: en
  `"Study time: “\(app)” is closing."`, it `"È tempo di studio: «\(app)» si chiude."`

## Sources/FamilyTimerCore/Replies.swift

1. `status(...)`: new last parameter `minecraftPlayed: Int? = nil`. When it is not nil and
   `Policy.minecraftRemaining(state, played: minecraftPlayed!, now: now, config: config, calendar: calendar)`
   is not nil, add a line right after the first two lines (before the study line):
   en `"Minecraft: played \(duration(played)) of \(duration(budget))\(extra). Remaining: \(duration(left))."`,
   it `"Minecraft: giocati \(duration(played)) su \(duration(budget))\(extra). Rimasti: \(duration(left))."`
   where `budget = DayLedger.minecraftBudget(for: now, config: config, calendar: calendar)` and
   `extra` is `" + \(duration(x)) extra"` when `state.ledger.minecraftExtra` is more than 0,
   otherwise `""`.
2. `reply(to:...)`: new last parameter `minecraftPlayed: Int? = nil`, passed to `status` and
   to `body` (add the same parameter to `body`).
3. `body`, `.minecraft(seconds)` (today it returns `""`): with
   `left = Policy.minecraftRemaining(state, played: minecraftPlayed ?? 0, now: now, config: config, calendar: calendar)`:
   - `left` not nil: en `"Minecraft: added \(duration(seconds)). Remaining: \(duration(left))."`,
     it `"Minecraft: aggiunti \(duration(seconds)). Rimasti: \(duration(left))."`
   - nil: en `"Minecraft: added \(duration(seconds)), but no Minecraft limit is set."`,
     it `"Minecraft: aggiunti \(duration(seconds)), ma non c'è un limite Minecraft."`
4. `help`: a new line right after the `/extra` line: en
   `"/minecraft 15m - more Minecraft today"`, it `"/minecraft 15m - più Minecraft oggi"`.

Existing tests must keep passing without changes.

## Tests/FamilyTimerCoreTests/BlockingTests.swift (new)

`final class BlockingTests: XCTestCase`. Copy the `calendar` and `at` helpers from
`MinecraftTests.swift`, and a config with `minecraftLimit: 2700, weekendMinecraftLimit: 3600`,
`language: .it`, `childNames: ["Art"]`.

1. `reason`: Minecraft with 0 left, not in studio -> `.minecraftOver`; with 600 left -> nil;
   with nil (no limit) -> nil; Minecraft in studio with 600 left -> `.studio`;
   `"app:com.apple.Terminal"` category `.coding` in studio -> `.studio`, not in studio -> nil;
   category `.video` in studio -> nil; category nil in studio -> nil;
   `"app:com.google.Chrome"` category `.games` in studio -> nil; `"site:github.com"`
   category `.coding` in studio -> nil.
2. Wire: `DaemonMessage(type: .close, app: "app:com.mojang.minecraft", reason: .minecraftOver)`
   encodes with `Wire.encode` to
   `{"app":"app:com.mojang.minecraft","reason":"minecraft_over","type":"close"}\n`
   and decodes back equal. A `state` message with `minecraftRemaining: 600` round-trips.
3. Texts: `AgentTexts.minecraftWarning(minutes: 5, .it) == "Minecraft: mancano 5 minuti per oggi."`;
   `AgentTexts.closed(app: "OpenCode", reason: .studio, .it) == "È tempo di studio: «OpenCode» si chiude."`.
4. Status: a fresh `PolicyState(ledger: DayLedger(day: "2026-11-23", used: 600))` at
   `at(10, 0)` with `minecraftPlayed: 1200`: the status contains the line
   `"Minecraft: giocati 20m su 45m. Rimasti: 25m."`; without `minecraftPlayed` it does not
   contain `"Minecraft"`.
5. Reply: after `.command(.minecraft(seconds: 900))` reduced with `Policy.reduce` at `at(10, 0)`,
   `Replies.reply(to: .minecraft(seconds: 900), after: s, now: at(10, 0), config: config, calendar: calendar, minecraftPlayed: 2700)`
   is `"Art: Minecraft: aggiunti 15m. Rimasti: 15m."`.
6. `Replies.help(.it)` contains `"/minecraft 15m - più Minecraft oggi"`.
