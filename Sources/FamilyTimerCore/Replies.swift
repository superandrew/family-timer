import Foundation

/// Texts the daemon sends to Telegram. Pure, so they are tested like the rest of the core.
public enum Replies {
    /// `3900` -> `"1h 05m"`, `2700` -> `"45m"`. Seconds are dropped.
    public static func duration(_ seconds: Int) -> String {
        let minutes = max(0, seconds) / 60
        if minutes >= 60 {
            return String(format: "%dh %02dm", minutes / 60, minutes % 60)
        }
        return "\(minutes)m"
    }

    /// `"14:05"` in the calendar's time zone.
    public static func clock(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    public static func phaseName(_ phase: Phase) -> String {
        switch phase {
        case .open: return "open"
        case .grace: return "time over, grace period"
        case .pending: return "waiting for a parent"
        case .locked: return "locked"
        }
    }

    public static func status(_ state: PolicyState, now: Date, config: Config,
                              calendar: Calendar) -> String {
        let budget = DayLedger.budget(for: now, config: config, calendar: calendar)
        let ledger = state.ledger
        var lines = [
            "\(config.childUser): used \(duration(ledger.used)) of \(duration(budget))"
                + (ledger.extra > 0 ? " + \(duration(ledger.extra)) extra" : "") + ".",
            "Remaining: \(duration(ledger.remaining(budget: budget))). State: \(phaseName(state.phase)).",
        ]
        if let until = ledger.studioUntil, ledger.inStudio(at: now) {
            lines.append("Study time until \(clock(until, calendar: calendar)).")
        }
        if ledger.lockedByParent {
            lines.append("Locked by a parent until midnight or /unlock.")
        }
        return lines.joined(separator: "\n")
    }

    /// The answer to a parent command, given the state after the command.
    public static func reply(to command: Command, after state: PolicyState, now: Date,
                             config: Config, calendar: Calendar) -> String {
        let remaining = Policy.remaining(state, now: now, config: config, calendar: calendar)
        switch command {
        case .status:
            return status(state, now: now, config: config, calendar: calendar)
        case .help:
            return help
        case let .extra(seconds):
            return "Added \(duration(seconds)). Remaining: \(duration(remaining))."
                + (state.ledger.lockedByParent ? " Still locked by /lock." : "")
        case .studio:
            let until = state.ledger.studioUntil.map { clock($0, calendar: calendar) } ?? "?"
            return "Study time until \(until): time does not count."
                + (state.ledger.lockedByParent ? " Still locked by /lock." : "")
        case .lock:
            return "Locked until midnight or /unlock."
        case .unlock:
            return state.phase == .locked
                ? "Parent lock removed, but no time is left: still locked. Use /extra or /studio."
                : "Unlocked. Remaining: \(duration(remaining))."
        }
    }

    public static func error(_ error: CommandError) -> String {
        switch error {
        case let .unknown(word):
            return "Unknown command \(word). /help lists the commands."
        case let .missingDuration(word):
            return "\(word) needs a duration, for example \(word) 30 or \(word) 1h30."
        case let .invalidDuration(text):
            return "\"\(text)\" is not a duration between 1 minute and 12 hours (30, 45m, 2h, 1h30)."
        }
    }

    public static let help = """
        /status - time used and left today
        /extra 30 - add time today (30, 45m, 2h, 1h30)
        /studio 2h - study time: the next 2 hours do not count
        /lock - lock until midnight or /unlock
        /unlock - remove /lock
        """

    public static func request(child: String, seconds: Int) -> String {
        "⏰ \(child) has used today's time and asks for \(duration(seconds)) more."
    }

    public static func decided(_ request: String, approved: Bool, by name: String) -> String {
        request + "\n" + (approved ? "✅ Approved" : "❌ Denied") + (name.isEmpty ? "" : " by \(name)") + "."
    }
}
