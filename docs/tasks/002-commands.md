+++
id = "002"
title = "Durations and Telegram commands"
edit = ["Sources/FamilyTimerCore/Commands.swift", "Tests/FamilyTimerCoreTests/CommandsTests.swift"]
read = ["Package.swift", "Tests/FamilyTimerCoreTests/VersionTests.swift"]
checks = ["test -s Sources/FamilyTimerCore/Commands.swift && test -s Tests/FamilyTimerCoreTests/CommandsTests.swift", "swift build", "swift test --filter CommandsTests", "swift test", "git add -N -- Sources/FamilyTimerCore/Commands.swift Tests/FamilyTimerCoreTests/CommandsTests.swift && git --no-pager diff --check HEAD"]
commit = "feat(core): parse durations and parent commands"
edit_format = "whole"
+++

# 002 - Durations and Telegram commands

Both files are new. Write them whole. Do not use `Regex` or `NSRegularExpression`:
parse with plain `String` operations as described.

## Sources/FamilyTimerCore/Commands.swift

    import Foundation

    public func parseDuration(_ text: String) -> Int?

    public enum Command: Equatable {
        case status
        case extra(seconds: Int)
        case studio(seconds: Int)
        case lock
        case unlock
        case help
    }

    public enum CommandError: Error, Equatable {
        case unknown(String)
        case missingDuration(String)
        case invalidDuration(String)
    }

    public func parseCommand(_ text: String) -> Result<Command, CommandError>

### parseDuration

Returns seconds, or nil.

1. `s` = `text` trimmed of whitespace, lowercased. Empty -> nil.
2. If every character of `s` is an ASCII digit: minutes = `Int(s)`.
3. Else if `s` ends with `"min"`: the part before must be all ASCII digits (at least one);
   minutes = that number.
4. Else if `s` ends with `"m"` and contains no `"h"`: the part before must be all ASCII
   digits (at least one); minutes = that number.
5. Else if `s` contains `"h"`: split at the first `"h"`. The part before must be all ASCII
   digits (at least one): hours. The part after is either empty, or all ASCII digits, or
   ASCII digits followed by one `"m"`: extra minutes, which must be 0...59.
   minutes = hours * 60 + extra minutes.
6. Anything else -> nil.
7. seconds = minutes * 60. Return nil unless `60 <= seconds && seconds <= 12 * 3600`.

### parseCommand

1. Trim `text`. Split on whitespace, dropping empty parts. No parts ->
   `.failure(.unknown(""))`.
2. `word` = first part, lowercased. If it contains `"@"`, keep only what comes before the
   first `"@"` (`"/extra@family_bot"` -> `"/extra"`).
3. `"/status"` -> `.status`; `"/lock"` -> `.lock`; `"/unlock"` -> `.unlock`;
   `"/help"` and `"/start"` -> `.help`.
4. `"/extra"` and `"/studio"` need the second part. Missing ->
   `.failure(.missingDuration(word))`. `parseDuration(second part)` nil ->
   `.failure(.invalidDuration(second part as typed))`. Otherwise `.extra(seconds:)` or
   `.studio(seconds:)`. Parts after the second are ignored.
5. Any other word -> `.failure(.unknown(word))`.

## Tests/FamilyTimerCoreTests/CommandsTests.swift

`final class CommandsTests: XCTestCase`, like `VersionTests.swift`.

`testDurations`: one `XCTAssertEqual(parseDuration(input), expected)` per row.

| input | expected |
|---|---|
| `"30"` | `30 * 60` |
| `"30m"` | `30 * 60` |
| `"45min"` | `45 * 60` |
| `"2h"` | `2 * 3600` |
| `" 2H "` | `2 * 3600` |
| `"1h30"` | `90 * 60` |
| `"1h30m"` | `90 * 60` |
| `"12h"` | `12 * 3600` |
| `"0"` | `nil` |
| `"13h"` | `nil` |
| `"1h75"` | `nil` |
| `"h"` | `nil` |
| `"abc"` | `nil` |
| `""` | `nil` |

`testCommands`: one `XCTAssertEqual(parseCommand(input), expected)` per row.

| input | expected |
|---|---|
| `"/status"` | `.success(.status)` |
| `"  /STATUS  "` | `.success(.status)` |
| `"/status@family_bot"` | `.success(.status)` |
| `"/extra 30"` | `.success(.extra(seconds: 30 * 60))` |
| `"/extra@family_bot 1h"` | `.success(.extra(seconds: 3600))` |
| `"/studio 2h please"` | `.success(.studio(seconds: 2 * 3600))` |
| `"/extra"` | `.failure(.missingDuration("/extra"))` |
| `"/studio xx"` | `.failure(.invalidDuration("xx"))` |
| `"/lock"` | `.success(.lock)` |
| `"/unlock"` | `.success(.unlock)` |
| `"/start"` | `.success(.help)` |
| `"/help"` | `.success(.help)` |
| `"ciao"` | `.failure(.unknown("ciao"))` |
| `"/foo bar"` | `.failure(.unknown("/foo"))` |
| `""` | `.failure(.unknown(""))` |
