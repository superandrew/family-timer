+++
id = "023"
title = "Time request with an optional reason: protocol, cleaning, texts"
edit = ["Sources/FamilyTimerCore/AgentProtocol.swift", "Sources/FamilyTimerCore/Replies.swift", "Sources/FamilyTimerCore/AgentTexts.swift", "Tests/FamilyTimerCoreTests/ReasonTests.swift"]
read = ["Tests/FamilyTimerCoreTests/MenuTests.swift"]
checks = ["test -s Tests/FamilyTimerCoreTests/ReasonTests.swift", "swift build", "swift test --filter ReasonTests", "swift test", "git add -N -- Tests/FamilyTimerCoreTests/ReasonTests.swift && git --no-pager diff --check HEAD"]
commit = "feat(core): a time request can carry what the child needs the time for"
edit_format = "diff"
+++

# 023 - What do you need the time for?

When the child asks for more time, the agent shows an optional text field "What do you need
it for?". The text goes to the daemon and appears in the parents' Telegram request. The
child's text is untrusted: it is cleaned and cut before it is shown. Existing tests must keep
passing without changes.

## Sources/FamilyTimerCore/AgentProtocol.swift

After `struct AgentReport` add:

    /// "Ask for more time" with what the child wrote (optional). Sent instead of the bare
    /// `request_time` message; the daemon cleans the text with `Replies.cleanReason`.
    public struct TimeRequest: Codable, Equatable {
        public var requestTime: Bool
        public var reason: String?

        public init(reason: String? = nil) {
            self.requestTime = true
            self.reason = reason
        }

        enum CodingKeys: String, CodingKey {
            case requestTime = "request_time"
            case reason
        }
    }

## Sources/FamilyTimerCore/Replies.swift

1. Add, right before `public static func request(`:

        /// The child's text, safe to show: control characters and new lines become spaces,
        /// runs of spaces become one, trimmed; nil when empty; longer than 120 characters is
        /// cut to 119 characters plus "…".
        public static func cleanReason(_ text: String?) -> String? {
            guard let text else { return nil }
            let spaced = String(text.map { $0.isNewline || ($0.unicodeScalars.first.map { CharacterSet.controlCharacters.contains($0) } ?? false) ? " " : $0 })
            let words = spaced.split(whereSeparator: { $0 == " " || $0 == "\t" })
            let joined = words.joined(separator: " ")
            if joined.isEmpty { return nil }
            if joined.count > 120 { return String(joined.prefix(119)) + "…" }
            return joined
        }

2. `request(child:seconds:remaining:_:)` gets a new parameter `reason: String? = nil` placed
   AFTER `remaining` and BEFORE the unnamed language parameter:

        public static func request(child: String, seconds: Int, remaining: Int? = nil,
                                   reason: String? = nil, _ l: Language) -> String

   Compute the text exactly as today into a local `text`; then, when `reason` is not nil,
   return `text + "\n" + t(l, "📝 What for: \(reason!)", "📝 Cosa deve fare: \(reason!)")`,
   otherwise return `text`.

## Sources/FamilyTimerCore/AgentTexts.swift

Add after `askButton`:

    public static func reasonPrompt(_ l: Language) -> String {
        t(l, "Ask for more time.\nWhat do you need it for? (optional)",
             "Chiedi altro tempo.\nCosa devi fare? (facoltativo)")
    }
    public static func reasonPlaceholder(_ l: Language) -> String {
        t(l, "e.g. finish my maths homework", "es. finire i compiti di matematica")
    }
    public static func sendButton(_ l: Language) -> String { t(l, "Send", "Invia") }
    public static func cancelButton(_ l: Language) -> String { t(l, "Cancel", "Annulla") }

## Tests/FamilyTimerCoreTests/ReasonTests.swift (new; its SEARCH section is empty)

`import XCTest`, `@testable import FamilyTimerCore`, `final class ReasonTests: XCTestCase`.

1. `testClean`:
   - `Replies.cleanReason(nil) == nil`, `Replies.cleanReason("") == nil`, `Replies.cleanReason("  \n ") == nil`
   - `Replies.cleanReason("  finire\n\ni compiti  ") == "finire i compiti"`
   - `Replies.cleanReason("a\tb\u{7}c") == "a b c"`
   - `let long = String(repeating: "x", count: 130)`: `Replies.cleanReason(long) == String(repeating: "x", count: 119) + "…"`
   - `Replies.cleanReason(String(repeating: "y", count: 120)) == String(repeating: "y", count: 120)`
2. `testRequestText`:
   - `Replies.request(child: "Art", seconds: 1800, reason: "compiti", .it) == "⏰ Art ha finito il tempo di oggi e chiede altri 30m.\n📝 Cosa deve fare: compiti"`
   - `Replies.request(child: "Art", seconds: 1800, remaining: 600, reason: "homework", .en) == "⏰ Art has 10m left and asks for 30m more.\n📝 What for: homework"`
   - `Replies.request(child: "Art", seconds: 1800, .it) == "⏰ Art ha finito il tempo di oggi e chiede altri 30m."`
3. `testWire`:
   - `String(data: Wire.encode(TimeRequest(reason: "compiti")), encoding: .utf8) == "{\"reason\":\"compiti\",\"request_time\":true}\n"`
   - decoding `Data("{\"request_time\":true}".utf8)` with `JSONDecoder` as `TimeRequest` gives `TimeRequest()`
   - decoding `Data("{\"accessibility\":true}".utf8)` as `TimeRequest` throws (`XCTAssertThrowsError`)
   - decoding `Data("{\"reason\":\"x\",\"request_time\":true}".utf8)` as `AgentReport` throws
4. `testTexts`: `AgentTexts.sendButton(.it) == "Invia"`, `AgentTexts.cancelButton(.it) == "Annulla"`,
   `AgentTexts.reasonPrompt(.it) == "Chiedi altro tempo.\nCosa devi fare? (facoltativo)"`.
