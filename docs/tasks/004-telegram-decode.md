+++
id = "004"
title = "Telegram updates decoding"
edit = ["Sources/FamilyTimerCore/Telegram.swift", "Tests/FamilyTimerCoreTests/TelegramTests.swift"]
read = ["Package.swift", "Sources/FamilyTimerCore/Config.swift", "Tests/FamilyTimerCoreTests/VersionTests.swift"]
checks = ["test -s Sources/FamilyTimerCore/Telegram.swift && test -s Tests/FamilyTimerCoreTests/TelegramTests.swift", "swift build", "swift test --filter TelegramTests", "swift test", "git add -N -- Sources/FamilyTimerCore/Telegram.swift Tests/FamilyTimerCoreTests/TelegramTests.swift && git --no-pager diff --check HEAD"]
commit = "feat(core): decode Telegram getUpdates and check parents"
edit_format = "whole"
+++

# 004 - Telegram updates decoding

Both files are new. Write them whole. `Config` exists already (task 001), read it, do not
edit it. No networking here: only JSON decoding.

## Sources/FamilyTimerCore/Telegram.swift

    import Foundation

    public enum TelegramError: Error, Equatable {
        case notOK(String)
    }

    public enum TelegramEvent: Equatable {
        case message(chatID: Int64, fromID: Int64, text: String)
        case callback(id: String, chatID: Int64, fromID: Int64, data: String)
        case other
    }

    public struct TelegramUpdate: Equatable {
        public var updateID: Int64
        public var event: TelegramEvent
    }

    public func decodeUpdates(_ data: Data) throws -> [TelegramUpdate]
    public func nextOffset(after updates: [TelegramUpdate]) -> Int64?
    public func isFromParent(chatID: Int64, fromID: Int64, config: Config) -> Bool

Decode with `JSONDecoder` into private `Decodable` structs that mirror the JSON below. Every
field is optional except `update_id`; keys are snake_case, map them with `CodingKeys`.

    {"ok": true, "description": "...", "result": [
      {"update_id": 1, "message": {"from": {"id": 11}, "chat": {"id": -100}, "text": "/status"}},
      {"update_id": 2, "callback_query": {"id": "cb1", "from": {"id": 11},
                                          "message": {"chat": {"id": -100}}, "data": "approve:r1"}}
    ]}

- `decodeUpdates`: if `ok` is not true, `throw TelegramError.notOK(description ?? "")`.
  Otherwise map each element of `result` (missing `result` -> `[]`), in order:
  - has `message` with `from.id`, `chat.id` and `text` -> `.message(...)`;
  - else has `callback_query` with `id`, `from.id`, `message.chat.id` and `data` ->
    `.callback(...)`;
  - else `.other`.
  Unknown JSON keys are ignored. Invalid JSON throws the `DecodingError` as it comes.
- `nextOffset`: `nil` for an empty array, else the largest `updateID` plus 1.
- `isFromParent`: false when `Int64(config.telegramChatID)` is nil or differs from `chatID`.
  Otherwise true when `config.parentUserIDs` is empty or contains `fromID`.

## Tests/FamilyTimerCoreTests/TelegramTests.swift

`final class TelegramTests: XCTestCase`, like `VersionTests.swift`. Build inputs with
`Data(json.utf8)` from Swift multi-line string literals. One test method per case:

1. The JSON above decodes to
   `[TelegramUpdate(updateID: 1, event: .message(chatID: -100, fromID: 11, text: "/status")),
   TelegramUpdate(updateID: 2, event: .callback(id: "cb1", chatID: -100, fromID: 11, data: "approve:r1"))]`.
   `TelegramUpdate` has no public init: use the memberwise init through `@testable import`.
2. `{"ok": true, "result": [{"update_id": 7, "message": {"from": {"id": 1}, "chat": {"id": 2}, "photo": []}}]}`
   decodes to one update with `updateID == 7` and `event == .other`.
3. `{"ok": true, "result": []}` decodes to `[]`, and `nextOffset(after: [])` is `nil`.
4. `{"ok": false, "description": "Unauthorized"}` throws
   `TelegramError.notOK("Unauthorized")`.
5. `"not json"` throws (any error).
6. `nextOffset(after:)` of the two updates of case 1 is `3`.
7. `isFromParent` with `Config(childUser: "a", telegramChatID: "-100", parentUserIDs: [11])`:
   `(chatID: -100, fromID: 11)` true; `(chatID: -100, fromID: 12)` false;
   `(chatID: -200, fromID: 11)` false.
   With `Config(childUser: "a", telegramChatID: "-100")`: `(chatID: -100, fromID: 12)` true.
   With `Config(childUser: "a")`: `(chatID: -100, fromID: 11)` false.
