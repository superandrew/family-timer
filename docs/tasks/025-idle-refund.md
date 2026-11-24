+++
id = "025"
title = "Idle refund: give back the seconds counted before idle was detected"
edit = ["Sources/FamilyTimerCore/DayLedger.swift", "Sources/FamilyTimerCore/Policy.swift", "Sources/FamilyTimerCore/Usage.swift", "Sources/FamilyTimerCore/IdleRefund.swift", "Tests/FamilyTimerCoreTests/IdleRefundTests.swift"]
read = ["Tests/FamilyTimerCoreTests/WeeklyTests.swift"]
checks = ["test -s Sources/FamilyTimerCore/IdleRefund.swift", "test -s Tests/FamilyTimerCoreTests/IdleRefundTests.swift", "swift build", "swift test --filter IdleRefundTests", "swift test", "git add -N -- Sources/FamilyTimerCore/IdleRefund.swift Tests/FamilyTimerCoreTests/IdleRefundTests.swift && git --no-pager diff --check HEAD"]
commit = "feat(core): seconds counted while nobody touched the Mac are given back when idle is detected"
edit_format = "diff"
+++

# 025 - Idle refund

The daemon counts a 15-second tick while the HID idle time is below `IDLE_THRESHOLD` (120 s).
So when the child walks away (music playing), up to 2 minutes are still counted before idle is
detected, and every time the child comes back to glance at the menu, another 2 minutes go.
From now on, when idle is detected, the seconds counted since the last input are given back:
to the day's ledger (computer time) and to the usage log (per app and site, so Minecraft too).

Existing tests must keep passing without changes.

## Sources/FamilyTimerCore/DayLedger.swift

After `public mutating func tick(seconds:active:now:)` add:

    /// Gives back seconds counted by mistake (idle refund). Never below zero.
    public mutating func refund(seconds: Int) {
        if seconds > 0 {
            used = max(0, used - seconds)
        }
    }

## Sources/FamilyTimerCore/Policy.swift

1. In `enum PolicyEvent`, after `case tick(seconds: Int, active: Bool)` add:

        /// Idle was detected: these seconds were counted after the child's last input.
        /// Only `open` gives them back (a phase change is never undone).
        case refund(seconds: Int)

2. In `Policy.reduce`, in the `switch event`, add a case right before `case .childLoggedIn:`:

        case let .refund(seconds):
            if s.phase == .open {
                s.ledger.refund(seconds: seconds)
            }

## Sources/FamilyTimerCore/Usage.swift

In `struct UsageLog`, right before `public func entries(from:to:)` add:

    /// Takes back seconds from `key` on `day` (idle refund). Never below zero; a key that
    /// reaches zero is removed from that day. Unknown day or key: nothing happens.
    public mutating func subtract(key: String, seconds: Int, day: String) {
        guard seconds > 0, let i = days.firstIndex(where: { $0.day == day }),
              let current = days[i].seconds[key] else { return }
        let left = current - seconds
        if left > 0 {
            days[i].seconds[key] = left
        } else {
            days[i].seconds.removeValue(forKey: key)
        }
    }

## Sources/FamilyTimerCore/IdleRefund.swift (new file)

    import Foundation

    /// Tracks the ticks counted while nobody touched the Mac, so they can be given back when
    /// the HID idle time reaches the threshold. Kept in memory by the daemon (not persisted).
    public struct IdleRefund: Equatable {
        /// Seconds counted since the last input.
        public private(set) var seconds: Int = 0
        /// The same seconds, per usage key (app and site keys), for `UsageLog.subtract`.
        public private(set) var keys: [String: Int] = [:]
        /// The day the seconds belong to.
        public private(set) var day: String?

        public init() {}

        /// Call after every counted tick. `idle`: HID idle seconds at this tick. If there was
        /// input during the tick (`idle < Double(seconds)`) the run starts again from zero and
        /// this tick is not refundable; otherwise this tick joins the run. A new `day` also
        /// starts again from zero.
        public mutating func counted(seconds: Int, idle: Double, keys newKeys: [String], day newDay: String) {
            if day != newDay {
                reset()
                day = newDay
            }
            if idle < Double(seconds) {
                reset()
                day = newDay
                return
            }
            self.seconds += seconds
            for key in newKeys {
                keys[key, default: 0] += seconds
            }
        }

        /// Call at a tick that was not counted. Returns what to give back (nil when nothing)
        /// and starts again from zero.
        public mutating func take() -> (seconds: Int, keys: [String: Int], day: String)? {
            defer { reset(); day = nil }
            guard seconds > 0, let day else { return nil }
            return (seconds, keys, day)
        }

        private mutating func reset() {
            seconds = 0
            keys = [:]
        }
    }

## Tests/FamilyTimerCoreTests/IdleRefundTests.swift (new file)

Write `final class IdleRefundTests: XCTestCase` with `@testable import FamilyTimerCore`, the
same `calendar`, `config`, `at(...)`, `reduce(...)` and `state(...)` helpers as in
`WeeklyTests.swift`, and these tests:

1. `testLedgerRefund`: `DayLedger(day: "2026-11-23", used: 100)`, `refund(seconds: 30)` gives
   used 70; `refund(seconds: 500)` then gives 0; `refund(seconds: -5)` leaves 0.
2. `testPolicyRefundInOpen`: `reduce(state(used: 1000), .refund(seconds: 120), at(10, 0))`
   gives `ledger.used == 880`, phase `.open`, no actions.
3. `testPolicyRefundIgnoredOutsideOpen`: for each phase `.grace`, `.pending`, `.locked`,
   `reduce(state(used: 3600, phase: phase), .refund(seconds: 120), at(10, 0)).0.ledger.used`
   is 3600.
4. `testUsageSubtract`: a `UsageLog` with `add(Frontmost(bundleID: "a", name: "A"), seconds:
   100, day: "2026-11-23")`; `subtract(key: "app:a", seconds: 30, day: "2026-11-23")` gives
   `total(for: "app:a") == 70`; subtracting 100 more removes the key
   (`days[0].seconds["app:a"] == nil`); subtracting on "2026-11-22" or key "app:zz" does nothing
   and does not crash.
5. `testRunIsRefunded`: `var r = IdleRefund()`; `counted(seconds: 15, idle: 3, keys: ["app:a"],
   day: "d")` (input: not refundable), then `counted(seconds: 15, idle: 18, keys: ["app:a",
   "site:x"], day: "d")` and `counted(seconds: 15, idle: 33, keys: ["app:a"], day: "d")`;
   `take()` returns seconds 30, keys `["app:a": 30, "site:x": 15]`, day "d"; a second `take()`
   returns nil.
6. `testInputResetsRun`: two refundable ticks (idle 20 and 35), then one with idle 2, then
   `take()` returns nil.
7. `testNewDayResetsRun`: a refundable tick on day "d1" (idle 20), then a refundable tick on
   day "d2" (idle 35); `take()` returns seconds 15, day "d2".
8. `testTakeWithoutTicks`: `IdleRefund().take()` (on a `var`) returns nil.
