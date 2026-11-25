+++
id = "026"
title = "A request that timed out no longer blocks a new one"
edit = ["Sources/FamilyTimerCore/Policy.swift", "Tests/FamilyTimerCoreTests/ExpiredRequestTests.swift"]
read = ["Tests/FamilyTimerCoreTests/PolicyTests.swift"]
checks = ["test -s Tests/FamilyTimerCoreTests/ExpiredRequestTests.swift", "swift build", "swift test --filter ExpiredRequestTests", "swift test", "git add -N -- Tests/FamilyTimerCoreTests/ExpiredRequestTests.swift && git --no-pager diff --check HEAD"]
commit = "fix(core): a request nobody answered no longer stops the child from asking again"
edit_format = "diff"
+++

# 026 - Expired requests

A request survives the lock, so a late Approve still works. But while `s.request` is set the
child cannot ask again, until midnight: a request nobody answered in `APPROVAL_TIMEOUT` blocks
every later one. From now on, once its deadline has passed, the child may ask again; the new
request replaces the old one (whose Telegram message says it is no longer needed). Until the
child asks again a late Approve of the old request still works, as today.

Existing tests must keep passing without changes.

## Sources/FamilyTimerCore/Policy.swift

1. In `public static func askState(...)`, replace the line

        if s.request != nil { return .waiting }

   with

        // A request past its deadline no longer blocks a new one (only when `now` is known).
        if let request = s.request, !(now.map { $0 >= request.deadline } ?? false) {
            return .waiting
        }

2. In `Policy.reduce`, in `case let .askForTime(requestID):`, replace

            guard s.phase == .grace || s.phase == .locked || early, s.request == nil,
                  s.askDenied != true, !s.ledger.lockedByParent else { break }

   with

            let expired = s.request.map { now >= $0.deadline } ?? true
            guard s.phase == .grace || s.phase == .locked || early, expired,
                  s.askDenied != true, !s.ledger.lockedByParent else { break }

3. In the same case, replace

            s.ledger.countRequest()
            s.request = PendingRequest(

   with

            s.ledger.countRequest()
            supersedeRequest(&s, actions: &actions)
            s.request = PendingRequest(

## Tests/FamilyTimerCoreTests/ExpiredRequestTests.swift (new file, its SEARCH section is empty)

Write `final class ExpiredRequestTests: XCTestCase` with `@testable import FamilyTimerCore`
and the same `calendar`, `config`, `at(...)`, `reduce(...)`, `state(...)`, `inGrace()`,
`inPending()` and `lockedWithRequest()` helpers as in `PolicyTests.swift` (copy them).
Add this helper:

    func askState(_ s: PolicyState, _ now: Date) -> AskState {
        Policy.askState(s, config: config, now: now, calendar: calendar)
    }

Tests (`lockedWithRequest()`: request r1, deadline 10:11, locked at 10:05):

1. `testAskStateAfterDeadline`: with `let s = lockedWithRequest()`,
   `askState(s, at(10, 10))` is `.waiting`, `askState(s, at(10, 11))` is `.available`, and
   `Policy.askState(s, config: config)` (no `now`) is `.waiting`.
2. `testAskBeforeDeadlineIsIgnored`: `let s = lockedWithRequest()`;
   `let (s2, actions) = reduce(s, .askForTime(requestID: "r2"), at(10, 10))`;
   `XCTAssertEqual(s2, s)` and `XCTAssertEqual(actions, [])`.
3. `testAskAfterDeadlineReplacesRequest`:
   `let (s, actions) = reduce(lockedWithRequest(), .askForTime(requestID: "r2"), at(10, 20))`;
   `s.phase` is `.locked`;
   `s.request` equals `PendingRequest(id: "r2", seconds: 1800, deadline: at(10, 30))`;
   `actions` equals `[.cancelRequest(requestID: "r1"), .sendTimeRequest(requestID: "r2", seconds: 1800)]`;
   `askState(s, at(10, 21))` is `.waiting`.
4. `testOldApproveAfterNewAskIsIgnored`:
   `let (s1, _) = reduce(lockedWithRequest(), .askForTime(requestID: "r2"), at(10, 20))`;
   `let (s, actions) = reduce(s1, .answer(requestID: "r1", approved: true), at(10, 21))`;
   `XCTAssertEqual(s, s1)` and `XCTAssertEqual(actions, [])`.
5. `testLateApproveStillWorksWithoutNewAsk`:
   `let (s, actions) = reduce(lockedWithRequest(), .answer(requestID: "r1", approved: true), at(10, 30))`;
   `s.phase` is `.open`, `s.ledger.extra` is 1800, `s.request` is nil,
   `actions` equals `[.requestResult(requestID: "r1", approved: true), .unlock]`.
6. `testExpiredEarlyRequestDoesNotBlockGrace`:
   `let (s1, _) = reduce(state(used: 2700), .askForTime(requestID: "r1"), at(9, 0))` (early:
   900 s left; deadline 9:10);
   `let (s2, _) = reduce(s1, .tick(seconds: 900, active: true), at(9, 20))`;
   `s2.phase` is `.grace`; `askState(s2, at(9, 20))` is `.available`;
   `let (s3, actions) = reduce(s2, .askForTime(requestID: "r2"), at(9, 21))`;
   `s3.phase` is `.pending`, `s3.request?.id` is "r2",
   `actions` equals `[.cancelRequest(requestID: "r1"), .sendTimeRequest(requestID: "r2", seconds: 1800)]`.
