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
