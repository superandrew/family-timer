+++
id = "011"
title = "AgentWatch: restart a missing agent, then tell the parents"
edit = ["Sources/FamilyTimerCore/AgentWatch.swift", "Tests/FamilyTimerCoreTests/AgentWatchTests.swift"]
read = ["Package.swift", "Tests/FamilyTimerCoreTests/VersionTests.swift"]
checks = ["test -s Sources/FamilyTimerCore/AgentWatch.swift && test -s Tests/FamilyTimerCoreTests/AgentWatchTests.swift", "swift build", "swift test --filter AgentWatchTests", "swift test", "git add -N -- Sources/FamilyTimerCore/AgentWatch.swift Tests/FamilyTimerCoreTests/AgentWatchTests.swift && git --no-pager diff --check HEAD"]
commit = "feat(core): AgentWatch decides when to restart the agent and when to tell the parents"
edit_format = "whole"
+++

# 011 - AgentWatch

Both files are new. Write them whole. Pure logic: no clock, the time is the `now` parameter.

The daemon calls `check` every 15 s. It says whether the child is at the console and whether
the agent (the menu bar app) is connected. `AgentWatch` answers what to do: nothing, restart
the agent, tell the parents it is missing, or tell them it is back.

## Sources/FamilyTimerCore/AgentWatch.swift

    import Foundation

    public enum AgentWatchAction: Equatable {
        case restart
        case notifyMissing
        case notifyBack
    }

    public struct AgentWatch: Equatable {
        public static let wait: TimeInterval = 60
        public static let maxRestarts = 2

        public var missingSince: Date?
        public var lastRestart: Date?
        public var restarts: Int
        public var notified: Bool

        public init()   // all nil, 0, false

        public mutating func check(now: Date, childAtConsole: Bool, agentConnected: Bool) -> AgentWatchAction?
    }

`check`, rules in this order (the first that applies returns):

1. `agentConnected` is true: remember `wasNotified = notified`, then set `missingSince = nil`,
   `lastRestart = nil`, `restarts = 0`, `notified = false`. Return `.notifyBack` if
   `wasNotified`, else `nil`.
2. `childAtConsole` is false: set `missingSince = nil`, `lastRestart = nil`, `restarts = 0`.
   Do not change `notified`. Return `nil`.
3. `missingSince` is nil: set `missingSince = now`, return `nil`.
4. Let `since = lastRestart ?? missingSince!`. If `now.timeIntervalSince(since) < AgentWatch.wait`,
   return `nil`.
5. `restarts < AgentWatch.maxRestarts`: `restarts += 1`, `lastRestart = now`, return `.restart`.
6. `notified` is false: `notified = true`, `lastRestart = now`, return `.notifyMissing`.
7. Return `nil`.

## Tests/FamilyTimerCoreTests/AgentWatchTests.swift

`final class AgentWatchTests: XCTestCase`, like `VersionTests.swift`. Use
`let t0 = Date(timeIntervalSince1970: 1_000_000)` and `t0 + seconds` (`Date` + `TimeInterval`).
Write a small helper in the test class:

    func run(_ w: inout AgentWatch, _ s: TimeInterval, console: Bool = true, connected: Bool = false) -> AgentWatchAction? {
        w.check(now: t0 + s, childAtConsole: console, agentConnected: connected)
    }

One test method per case, each starting from `var w = AgentWatch()`:

1. Missing agent, child at the console, checks at 0, 15, 60, 75, 120, 180, 240, 600 return
   `nil, nil, .restart, nil, .restart, .notifyMissing, nil, nil`. After them
   `w.restarts == 2` and `w.notified == true`.
2. Agent connected at 0 and at 60 returns `nil` both times; `w.missingSince == nil`.
3. Missing at 0, 60 (`.restart`), then connected at 70 returns `nil` and `w.restarts == 0`.
   Then missing again at 80 returns `nil`, at 139 `nil`, at 140 `.restart`.
4. Like case 1 up to 180 (`.notifyMissing`), then connected at 200 returns `.notifyBack`,
   `w.notified == false`, and connected at 215 returns `nil`.
5. Child not at the console: checks at 0, 60, 120, 180 with `console: false` all return `nil`
   and `w.missingSince == nil`.
6. Missing at 0, `.restart` at 60, then `console: false` at 70 returns `nil` and
   `w.restarts == 0`; back at the console: 80 `nil`, 140 `.restart`.
7. After `.notifyMissing` (case 1 up to 180), `console: false` at 200 returns `nil` and
   `w.notified` is still `true`; back at the console without the agent: 210 `nil`, 270
   `.restart`, 330 `.restart`, 390 `nil` (already notified).
