+++
id = "012"
title = "Ask for more time while locked; a denial holds until midnight"
edit = ["Sources/FamilyTimerCore/Policy.swift", "Sources/FamilyTimerCore/AgentProtocol.swift", "Sources/FamilyTimerCore/AgentTexts.swift", "Tests/FamilyTimerCoreTests/PolicyTests.swift", "Tests/FamilyTimerCoreTests/AgentProtocolTests.swift"]
read = ["Sources/FamilyTimerCore/Config.swift", "Sources/FamilyTimerCore/DayLedger.swift"]
checks = ["swift build", "swift test --filter PolicyTests", "swift test --filter AgentProtocolTests", "swift test", "git --no-pager diff --check HEAD"]
commit = "feat(core): ask for more time while locked; a denial holds until midnight"
edit_format = "diff"
+++

# 012 - Ask for more time while locked

Today the child can ask for more time only during the grace period. From now on the child
can also ask while `locked` (the agent shows a small window when the child unlocks the screen;
that is not part of this task). Rules: one request at a time, and after a parent says no, no
more requests until midnight, unless a parent gives time with `/extra`, `/studio` or `/unlock`.

All files exist. Change only what is listed here; keep everything else as it is.

## Sources/FamilyTimerCore/Policy.swift

1. In `PolicyState`, after `lockConfirmedAt`, add:

        /// A parent denied a request today: no new request until midnight or a parent's
        /// /extra, /studio or /unlock. Optional so that state files without it still decode.
        public var askDenied: Bool?

   Add the parameter `askDenied: Bool? = nil` at the end of `init` and assign it.

2. After `PolicyAction`, add:

        /// What the child can do about more time, sent to the agent with every state message.
        public enum AskState: String, Codable, Equatable {
            case available
            case waiting
            case denied
            case unavailable
        }

3. In `enum Policy`, after `remaining(...)`, add:

        public static func askState(_ s: PolicyState, config: Config) -> AskState {
            if s.request != nil { return .waiting }
            if s.askDenied == true { return .denied }
            if config.telegramBotToken.isEmpty || s.ledger.lockedByParent { return .unavailable }
            return s.phase == .grace || s.phase == .locked ? .available : .unavailable
        }

4. In `reduce`, `case let .askForTime(requestID):`
   - replace the guard with:

            guard s.phase == .grace || s.phase == .locked, s.request == nil,
                  s.askDenied != true, !s.ledger.lockedByParent else { break }

   - replace `s.phase = .pending` with:

            if s.phase == .grace {
                s.phase = .pending
            }

   Everything else in that case stays.

5. In `case let .answer(requestID, approved):` replace

        } else if s.phase == .pending {
            lock(&s, now: now, actions: &actions)
        }

   with

        } else {
            s.askDenied = true
            if s.phase == .pending {
                lock(&s, now: now, actions: &actions)
            }
        }

6. In `case let .command(command):`, add `s.askDenied = nil` as the first line of the
   `.extra`, `.studio` and `.unlock` cases.

## Sources/FamilyTimerCore/AgentProtocol.swift

In `DaemonMessage` add `public var askState: AskState?` after `approved`, with the doc comment
`/// \`state\`: what the child can do about more time.`, and the parameter
`askState: AskState? = nil` at the end of `init` (assign it). Nothing else changes.

## Sources/FamilyTimerCore/AgentTexts.swift

Add after `result(approved:_:)`, same style (`t(l, english, italian)`):

    public static func lockedAsk(_ l: Language) -> String
        "Today's time is over. You can ask a parent for more time."
        "Il tempo di oggi è finito. Puoi chiedere altro tempo ai genitori."
    public static func lockedWaiting(_ l: Language) -> String
        "Request sent. Waiting for a parent's answer."
        "Richiesta inviata. Aspetta la risposta dei genitori."
    public static func lockedDenied(_ l: Language) -> String
        "A parent said no: today's time is over."
        "Un genitore ha detto no: per oggi il tempo è finito."
    public static func lockedOver(_ l: Language) -> String
        "Today's time is over."
        "Il tempo di oggi è finito."

## Tests/FamilyTimerCoreTests/PolicyTests.swift

Keep every existing test. Add after `lockedWithRequest()` the helper:

    /// Locked at 10:05 at the end of grace, no request.
    func lockedNoRequest() -> PolicyState {
        let (s, _) = reduce(inGrace(), .tick(seconds: 15, active: true), at(10, 5))
        return s
    }

Add these tests in a `// MARK: asking while locked` section before `// MARK: persistence`:

1. `testAskWhileLockedSendsRequestAndStaysLocked`: `reduce(lockedNoRequest(), .askForTime(requestID: "r2"), at(10, 20))`
   gives `phase == .locked`, `request == PendingRequest(id: "r2", seconds: 1800, deadline: at(10, 30))`,
   actions `[.sendTimeRequest(requestID: "r2", seconds: 1800)]`, and
   `Policy.askState(s, config: config) == .waiting`.
2. `testApproveWhileLockedUnlocks`: from the state of test 1, `.answer(requestID: "r2", approved: true)`
   at 10:21 gives `phase == .open`, `ledger.extra == 1800`, actions
   `[.requestResult(requestID: "r2", approved: true), .unlock]`.
3. `testDenyBlocksFurtherAsks`: from the state of test 1, `.answer(requestID: "r2", approved: false)`
   at 10:21 gives `phase == .locked`, `askDenied == true`, actions
   `[.requestResult(requestID: "r2", approved: false)]`, `askState == .denied`. Then
   `.askForTime(requestID: "r3")` at 10:30 returns the same state and actions `[]`.
4. `testDenyInPendingAlsoBlocks`: `reduce(inPending(), .answer(requestID: "r1", approved: false), at(10, 2))`
   gives `askDenied == true` and `askState == .denied`.
5. `testParentTimeClearsDenial`: let `denied` be the state after test 3's answer. Each of
   `.command(.extra(seconds: 600))`, `.command(.studio(seconds: 600))` and `.command(.unlock)`
   at 10:40, applied to `denied`, gives `askDenied == nil`. After `.unlock` the phase is still
   `.locked` (no time left) and `askState == .available`.
6. `testNoAskDuringParentLock`: `reduce(lockedNoRequest(), .command(.lock), at(10, 10))`, then
   `.askForTime(requestID: "r4")` at 10:11 gives `request == nil`, actions `[]` and
   `askState == .unavailable`.
7. `testAskState`: `state()` -> `.unavailable`; `inGrace()` -> `.available`; `inPending()` ->
   `.waiting`; `lockedNoRequest()` -> `.available`; `lockedNoRequest()` with a copy of `config`
   whose `telegramBotToken = ""` -> `.unavailable`.
8. `testStateWithoutAskDeniedDecodes`: encode `lockedNoRequest()` with `JSONEncoder`; the JSON
   string does not contain `"askDenied"`, and decoding it gives back `lockedNoRequest()`.

## Tests/FamilyTimerCoreTests/AgentProtocolTests.swift

Keep every existing test. Add:

- `testAskStateWire`: `DaemonMessage(type: .state, askState: .denied)` encoded with
  `Wire.encode` contains `"askState":"denied"`, and decoding the line without its last byte
  (the newline) gives back the same message.
- `testLockedTexts`: `AgentTexts.lockedDenied(.it) == "Un genitore ha detto no: per oggi il tempo è finito."`
  and `AgentTexts.lockedAsk(.en) == "Today's time is over. You can ask a parent for more time."`.
