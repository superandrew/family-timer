+++
id = "017"
title = "A new login while locked gets time for the agent to start and lock"
edit = ["Sources/FamilyTimerCore/Policy.swift", "Tests/FamilyTimerCoreTests/PolicyTests.swift"]
read = []
checks = ["swift build", "swift test --filter PolicyTests", "swift test", "git --no-pager diff --check HEAD"]
commit = "fix(core): a new login while locked gets 90 s before the logout fallback"
edit_format = "diff"
+++

# 017 - Login grace while locked

Bug seen on a real Mac: time over (phase `locked`), the Mac restarts, the child logs in.
`lockSentAt` is from an hour ago, so the first active tick logs the child out at once, before
the menu bar agent has even started. Every new login is logged out again 30 s later. The
agent can never start and lock the screen, so the child sees only logouts.

Fix: two new events that move the logout deadline forward. Nothing else changes.

## Sources/FamilyTimerCore/Policy.swift

In `PolicyEvent`, after `lockConfirmed`, add:

    /// The child's session has just appeared at the console (login, fast user switch).
    case childLoggedIn
    /// The agent connected to the daemon (its `hello`).
    case agentConnected

In `Policy`, next to `lockConfirmTimeout`, add:

    /// After a login while locked, seconds before the logout fallback: the agent may need
    /// up to 60 s to be restarted by the daemon, then it has to lock.
    public static let loginGrace: TimeInterval = 90

In `reduce`, handle them next to `.lockConfirmed`:

- `.childLoggedIn`: only when `s.phase == .locked`: set
  `s.lockSentAt = now.addingTimeInterval(loginGrace - lockConfirmTimeout)` and
  `s.lockConfirmedAt = nil`. No actions. In any other phase: no change, no actions.
- `.agentConnected`: only when `s.phase == .locked`: if `s.lockSentAt` is nil or earlier than
  `now`, set `s.lockSentAt = now`. Do not touch `lockConfirmedAt`. No actions. In any other
  phase: no change, no actions.

The existing logout rule in `.locked` stays as it is: it logs out when
`now - lockSentAt >= lockConfirmTimeout` and the lock was not confirmed recently, so a
`lockSentAt` in the future simply waits.

## Tests/FamilyTimerCoreTests/PolicyTests.swift

Add these methods under `// MARK: lock confirmation and logout`. Use the existing helpers
`lockedWithRequest()` (locked at 10:05), `state()`, `reduce`, `at(h, m, s)`.

1. `testLoginWhileLockedWaitsBeforeLogout`: from `lockedWithRequest()`, `.childLoggedIn` at
   `at(11, 0)` gives `lockSentAt == at(11, 1)`, `lockConfirmedAt == nil`, actions `[]`. Then
   active ticks (`.tick(seconds: 15, active: true)`): at `at(11, 0, 30)` actions `[]`, at
   `at(11, 1, 15)` actions `[]`, at `at(11, 1, 30)` actions `[.logout]`. Chain the states.
2. `testAgentConnectedRestartsTheLockWindow`: from `lockedWithRequest()`, `.agentConnected` at
   `at(11, 0)` gives `lockSentAt == at(11, 0)` and actions `[]`; an active tick at
   `at(11, 0, 15)` gives `[]`, at `at(11, 0, 30)` gives `[.logout]`.
3. `testAgentConnectedKeepsTheLoginGrace`: `.childLoggedIn` at `at(11, 0)`, then
   `.agentConnected` at `at(11, 0, 10)`: `lockSentAt` is still `at(11, 1)`.
4. `testLoginEventsOutsideLockedAreIgnored`: on `state()`, `.childLoggedIn` and
   `.agentConnected` at `at(9, 0)` each return a state equal to `state()` and actions `[]`.

Do not change the existing tests.
