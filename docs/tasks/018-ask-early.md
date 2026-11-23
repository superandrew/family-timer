+++
id = "018"
title = "Ask for more time before it runs out (last 15 minutes)"
edit = ["Sources/FamilyTimerCore/Policy.swift", "Sources/FamilyTimerCore/Replies.swift", "Tests/FamilyTimerCoreTests/PolicyTests.swift", "Tests/FamilyTimerCoreTests/RepliesTests.swift"]
read = []
checks = ["swift build", "swift test --filter PolicyTests", "swift test --filter RepliesTests", "swift test", "git --no-pager diff --check HEAD"]
commit = "feat(core): ask for more time in the last 15 minutes, before the time runs out"
edit_format = "diff"
+++

# 018 - Ask early

Today the child can ask for more time only after the time is over (grace) or while locked.
The child should also be able to ask in the last 15 minutes, while the phase is still
`open`, so the answer may arrive before the screen locks. The other rules do not change:
one request at a time, a "no" holds until midnight (`askDenied`), nothing during a parent
lock.

## Sources/FamilyTimerCore/Policy.swift

1. In `Policy`, next to `lockConfirmTimeout`, add:

       /// In `open`, the child can ask for more time when this many seconds or fewer are left.
       public static let askEarlyWindow = 900

2. `askForTime`: today the guard is
   `s.phase == .grace || s.phase == .locked, s.request == nil, s.askDenied != true, !s.ledger.lockedByParent`.
   Allow also `open` when `s.ledger.remaining(budget: budget) <= askEarlyWindow` and
   `!s.ledger.inStudio(at: now)`. Write it as a local `let early = s.phase == .open && ...`
   and use `s.phase == .grace || s.phase == .locked || early` in the guard. The rest of the
   case stays as it is: in `open` the phase does not change (only grace goes to pending).

3. `.tick` in `.open`: when the time runs out (the existing `remaining == 0 && !inStudio`
   branch), if `s.request != nil` set `s.phase = .pending` instead of `.grace`. `graceUntil`
   and the `.showExpiredDialog` action stay the same in both cases.

4. `.answer`: no change is needed. Check that approving in `open` gives the extra seconds and
   no `.unlock` action, and that denying in `open` sets `askDenied` and keeps `open`.

5. `askState`: change the signature to

       public static func askState(_ s: PolicyState, config: Config, now: Date? = nil,
                                   calendar: Calendar = .current) -> AskState

   Same rules as today, plus: in `open`, `.available` when `now` is not nil,
   `remaining(s, now: now!, config: config, calendar: calendar) <= askEarlyWindow` and
   `!s.ledger.inStudio(at: now!)`. Otherwise `open` stays `.unavailable`. The order of the
   checks does not change (request -> waiting, askDenied -> denied, no token or parent lock ->
   unavailable). Existing calls without `now` keep working.

## Sources/FamilyTimerCore/Replies.swift

Add a parameter to `request`:

    public static func request(child: String, seconds: Int, remaining: Int? = nil, _ l: Language) -> String

When `remaining` is nil or 0, the text is the current one. Otherwise:
- en: `"⏰ \(child) has \(duration(remaining)) left and asks for \(duration(seconds)) more."`
- it: `"⏰ \(child) ha ancora \(duration(remaining)) e chiede altri \(duration(seconds))."`

## Tests

`PolicyTests.swift`, new section `// MARK: asking early`. Use `state(used:)` (weekday limit
3600, so `used: 3000` leaves 600 s), `at(9, 0)`, `reduce`, `config`, `calendar` as the other
tests do. New methods:

1. `testAskEarlyInTheLastMinutes`: `state(used: 3000)` + `.askForTime(requestID: "e1")` at
   `at(9, 0)`: phase `.open`, `request == PendingRequest(id: "e1", seconds: 1800, deadline: at(9, 10))`,
   actions `[.sendTimeRequest(requestID: "e1", seconds: 1800)]`.
2. `testNoAskEarlyWithMoreThan15Minutes`: `state(used: 2000)` + `.askForTime` at `at(9, 0)`:
   state unchanged, actions `[]`.
3. `testApproveEarlyAddsTime`: from case 1, `.answer(requestID: "e1", approved: true)` at
   `at(9, 1)`: phase `.open`, `ledger.extra == 1800`, `request == nil`, actions
   `[.requestResult(requestID: "e1", approved: true)]`.
4. `testDenyEarlyStaysOpenAndBlocks`: from case 1, deny at `at(9, 1)`: phase `.open`,
   `askDenied == true`, actions `[.requestResult(requestID: "e1", approved: false)]`.
5. `testRunningOutWhileWaitingGoesToPending`: `state(used: 3600 - 15)` + `.askForTime(requestID: "e2")`
   at `at(9, 0)`, then `.tick(seconds: 15, active: true)` at `at(9, 0, 15)`: phase
   `.pending`, `graceUntil == at(9, 5, 15)`, actions `[.showExpiredDialog]`.
6. `testAskStateEarly`: `Policy.askState(state(used: 3000), config: config, now: at(9, 0), calendar: calendar)`
   is `.available`; with `state(used: 2000)` it is `.unavailable`; with `state(used: 3000)`
   and no `now` it is `.unavailable`.

`RepliesTests.swift`: add to an existing test or a new one:
- `Replies.request(child: "arthur", seconds: 1800, remaining: 240, .it) == "⏰ arthur ha ancora 4m e chiede altri 30m."`
- `Replies.request(child: "arthur", seconds: 1800, remaining: 240, .en) == "⏰ arthur has 4m left and asks for 30m more."`

Check the format of `duration` in the existing tests (`30m`, `4m`) before writing the
expected strings. Do not change the existing tests.
