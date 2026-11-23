+++
id = "022"
title = "Approve a time request with a chosen amount: 2m, 5m, 30m, 1h"
edit = ["Sources/FamilyTimerCore/Policy.swift", "Sources/FamilyTimerCore/Commands.swift", "Sources/FamilyTimerCore/Replies.swift", "Tests/FamilyTimerCoreTests/AnswerTests.swift"]
read = ["Tests/FamilyTimerCoreTests/PolicyTests.swift", "Sources/FamilyTimerCore/DayLedger.swift"]
checks = ["test -s Tests/FamilyTimerCoreTests/AnswerTests.swift", "swift build", "swift test --filter AnswerTests", "swift test", "git add -N -- Tests/FamilyTimerCoreTests/AnswerTests.swift && git --no-pager diff --check HEAD"]
commit = "feat(core): approve a time request with a chosen amount (2m, 5m, 30m, 1h)"
edit_format = "diff"
+++

# 022 - Approve with a chosen amount

Today the Telegram request has two buttons, Approve (adds `EXTENSION_TIME`) and Deny. The
parents want to choose how much: 2m, 5m, 30m, 1h. The buttons will carry the amount in their
callback data, `approve:<requestID>:<seconds>`. Old messages still have `approve:<requestID>`
(no amount: the request's own seconds). Existing tests must keep passing without changes.

## Sources/FamilyTimerCore/Policy.swift

1. In `enum PolicyEvent`, the case

        case answer(requestID: String, approved: Bool)

   becomes

        /// `seconds`: the amount the parent chose; nil = the request's own amount.
        case answer(requestID: String, approved: Bool, seconds: Int? = nil)

2. In `reduce`, the case `case let .answer(requestID, approved):` becomes
   `case let .answer(requestID, approved, seconds):` and the line
   `s.ledger.grantExtra(seconds: request.seconds)` becomes
   `s.ledger.grantExtra(seconds: seconds ?? request.seconds)`. Nothing else changes.

## Sources/FamilyTimerCore/Commands.swift

At the end of the file add:

    /// A press on a request button: `approve:<id>`, `approve:<id>:<seconds>` or `deny:<id>`.
    public struct AnswerData: Equatable {
        public var requestID: String
        public var approved: Bool
        public var seconds: Int?

        public init(requestID: String, approved: Bool, seconds: Int? = nil) {
            self.requestID = requestID
            self.approved = approved
            self.seconds = seconds
        }
    }

    public func parseAnswerData(_ data: String) -> AnswerData? {
        let parts = data.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2 || parts.count == 3, !parts[1].isEmpty else { return nil }
        guard parts[0] == "approve" || parts[0] == "deny" else { return nil }
        if parts.count == 2 {
            return AnswerData(requestID: parts[1], approved: parts[0] == "approve")
        }
        guard parts[0] == "approve", let seconds = Int(parts[2]), seconds > 0 else { return nil }
        return AnswerData(requestID: parts[1], approved: true, seconds: seconds)
    }

## Sources/FamilyTimerCore/Replies.swift

1. After `approveButton`, add:

        /// The amounts offered on a time request.
        public static let approveChoices = [120, 300, 1800, 3600]

        /// `"✅ 5m"`, `"✅ 1h"`.
        public static func approveChoiceButton(seconds: Int) -> String {
            seconds % 3600 == 0 ? "✅ \(seconds / 3600)h" : "✅ " + duration(seconds)
        }

2. `decided` gets a new LAST parameter `seconds: Int? = nil`. When `approved` and `seconds`
   is not nil, the outcome is en `"✅ Approved (+\(duration(seconds!)))"`, it
   `"✅ Approvato (+\(duration(seconds!)))"`; otherwise the outcome does not change. The rest
   (`who`, the final `"."`) does not change.

## Tests/FamilyTimerCoreTests/AnswerTests.swift (new; its SEARCH section is empty)

`import XCTest`, `@testable import FamilyTimerCore`, `final class AnswerTests: XCTestCase`.
Copy from `PolicyTests.swift` exactly: the `calendar` and `config` properties and the
functions `at`, `reduce`, `state`, `inGrace`, `inPending`, `lockedWithRequest`. Tests:

1. `testApproveWithAmount`:
   `let (s, actions) = reduce(inPending(), .answer(requestID: "r1", approved: true, seconds: 300), at(10, 2))`;
   `s.phase == .open`, `s.ledger.extra == 300`, `s.request == nil`,
   `actions == [.requestResult(requestID: "r1", approved: true)]`.
2. `testApproveWithoutAmountUsesRequest`:
   `reduce(inPending(), .answer(requestID: "r1", approved: true), at(10, 2))` gives `s.ledger.extra == 1800`.
3. `testLateApproveWithAmount`:
   `reduce(lockedWithRequest(), .answer(requestID: "r1", approved: true, seconds: 3600), at(10, 20))`:
   `s.phase == .open`, `s.ledger.extra == 3600`,
   `actions == [.requestResult(requestID: "r1", approved: true), .unlock]`.
4. `testParseAnswerData`:
   - `"approve:ab12"` -> `AnswerData(requestID: "ab12", approved: true)`
   - `"deny:ab12"` -> `AnswerData(requestID: "ab12", approved: false)`
   - `"approve:ab12:300"` -> `AnswerData(requestID: "ab12", approved: true, seconds: 300)`
   - nil for: `"deny:ab12:300"`, `"approve:ab12:0"`, `"approve:ab12:x"`, `"approve:"`,
     `"cat:app:x:games"`, `"approve"`, `"approve:ab12:300:1"`.
5. `testTexts`:
   - `Replies.approveChoices == [120, 300, 1800, 3600]`
   - `Replies.approveChoiceButton(seconds: 120) == "✅ 2m"`, `(seconds: 1800) == "✅ 30m"`,
     `(seconds: 3600) == "✅ 1h"`
   - `Replies.decided("Q", approved: true, by: "Ann", .it, seconds: 300) == "Q\n✅ Approvato (+5m) da Ann."`
   - `Replies.decided("Q", approved: true, by: "", .en, seconds: 3600) == "Q\n✅ Approved (+1h 00m)."`
   - `Replies.decided("Q", approved: false, by: "Ann", .it, seconds: 300) == "Q\n❌ Negato da Ann."`
