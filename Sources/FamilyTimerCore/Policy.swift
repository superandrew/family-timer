import Foundation

public enum Phase: String, Codable, Equatable {
    case open
    case grace
    case pending
    case locked
}

public struct PendingRequest: Codable, Equatable {
    public var id: String
    public var seconds: Int
    public var deadline: Date

    public init(id: String, seconds: Int, deadline: Date) {
        self.id = id
        self.seconds = seconds
        self.deadline = deadline
    }
}

/// Everything the daemon persists besides the config.
public struct PolicyState: Codable, Equatable {
    public var ledger: DayLedger
    public var phase: Phase
    /// End of the grace period, set in `grace` and `pending`.
    public var graceUntil: Date?
    /// The last time request. It survives the lock so that a late Approve still works;
    /// it is cleared when answered, superseded or at midnight.
    public var request: PendingRequest?
    /// When the lock was ordered (or the last logout), set in `locked`.
    public var lockSentAt: Date?
    /// The last time the agent confirmed that the screen is locked.
    public var lockConfirmedAt: Date?

    public init(ledger: DayLedger, phase: Phase = .open, graceUntil: Date? = nil,
                request: PendingRequest? = nil, lockSentAt: Date? = nil,
                lockConfirmedAt: Date? = nil) {
        self.ledger = ledger
        self.phase = phase
        self.graceUntil = graceUntil
        self.request = request
        self.lockSentAt = lockSentAt
        self.lockConfirmedAt = lockConfirmedAt
    }

    public static func fresh(for date: Date, calendar: Calendar) -> PolicyState {
        PolicyState(ledger: DayLedger.fresh(for: date, calendar: calendar))
    }
}

public enum PolicyEvent: Equatable {
    /// Every daemon tick. `active`: the console user is the child and HID idle time is
    /// below `IDLE_THRESHOLD`.
    case tick(seconds: Int, active: Bool)
    /// The child pressed "Ask for more time". `requestID` is made by the daemon.
    case askForTime(requestID: String)
    /// A parent pressed Approve or Deny (already checked with `isFromParent`).
    case answer(requestID: String, approved: Bool)
    /// A parent command (already checked with `isFromParent`).
    case command(Command)
    /// The agent reports that the screen is locked.
    case lockConfirmed
}

public enum PolicyAction: Equatable {
    /// Tell the agent to show the "time is over" dialog.
    case showExpiredDialog
    /// Send the request message with Approve / Deny buttons to Telegram.
    case sendTimeRequest(requestID: String, seconds: Int)
    /// Tell the agent the outcome of its request.
    case requestResult(requestID: String, approved: Bool)
    /// The request is no longer needed (a parent used a command, or a new day).
    case cancelRequest(requestID: String)
    /// Tell the agent to lock and keep re-locking.
    case lock
    /// Tell the agent to stop re-locking.
    case unlock
    /// Log the child out (`launchctl bootout gui/<uid>`): the agent did not confirm the lock.
    case logout
}

public enum Policy {
    /// Seconds the agent has to confirm a lock before the daemon logs the child out.
    public static let lockConfirmTimeout: TimeInterval = 30

    /// Remaining seconds of today, for `/status` and the agent's countdown.
    public static func remaining(_ state: PolicyState, now: Date, config: Config,
                                 calendar: Calendar) -> Int {
        state.ledger.remaining(budget: DayLedger.budget(for: now, config: config, calendar: calendar))
    }

    public static func reduce(_ state: PolicyState, _ event: PolicyEvent, now: Date,
                              config: Config, calendar: Calendar) -> (PolicyState, [PolicyAction]) {
        var s = state
        var actions: [PolicyAction] = []

        // A new day resets everything, whatever the event.
        if s.ledger.rolled(to: now, calendar: calendar) != s.ledger {
            if let request = s.request {
                actions.append(.cancelRequest(requestID: request.id))
            }
            if s.phase == .locked {
                actions.append(.unlock)
            }
            s = PolicyState.fresh(for: now, calendar: calendar)
        }

        let budget = DayLedger.budget(for: now, config: config, calendar: calendar)

        switch event {
        case let .tick(seconds, active):
            // Only `open` counts: grace is not charged to the granted extra time, and a
            // locked screen does not count even if someone touches it.
            if s.phase == .open {
                s.ledger.tick(seconds: seconds, active: active, now: now)
            }
            switch s.phase {
            case .open:
                if s.ledger.remaining(budget: budget) == 0 && !s.ledger.inStudio(at: now) {
                    s.phase = .grace
                    s.graceUntil = now.addingTimeInterval(TimeInterval(config.graceTime))
                    actions.append(.showExpiredDialog)
                }
            case .grace:
                if let until = s.graceUntil, now >= until {
                    lock(&s, now: now, actions: &actions)
                }
            case .pending:
                let graceOver = s.graceUntil.map { now >= $0 } ?? true
                let timedOut = s.request.map { now >= $0.deadline } ?? true
                if graceOver || timedOut {
                    lock(&s, now: now, actions: &actions)
                }
            case .locked:
                let sent = s.lockSentAt ?? now
                let confirmedRecently = s.lockConfirmedAt.map {
                    now.timeIntervalSince($0) < lockConfirmTimeout
                } ?? false
                if active && now.timeIntervalSince(sent) >= lockConfirmTimeout && !confirmedRecently {
                    actions.append(.logout)
                    // Give the agent of the next login the same time to lock.
                    s.lockSentAt = now
                    s.lockConfirmedAt = nil
                }
            }

        case let .askForTime(requestID):
            guard s.phase == .grace, s.request == nil else { break }
            if config.telegramBotToken.isEmpty {
                actions.append(.requestResult(requestID: requestID, approved: false))
                break
            }
            s.request = PendingRequest(
                id: requestID, seconds: config.extensionTime,
                deadline: now.addingTimeInterval(TimeInterval(config.approvalTimeout)))
            s.phase = .pending
            actions.append(.sendTimeRequest(requestID: requestID, seconds: config.extensionTime))

        case let .answer(requestID, approved):
            guard let request = s.request, request.id == requestID else { break }
            s.request = nil
            actions.append(.requestResult(requestID: requestID, approved: approved))
            if approved {
                s.ledger.grantExtra(seconds: request.seconds)
                reopen(&s, now: now, budget: budget, actions: &actions)
            } else if s.phase == .pending {
                lock(&s, now: now, actions: &actions)
            }

        case let .command(command):
            switch command {
            case .status, .help:
                break
            case let .extra(seconds):
                s.ledger.grantExtra(seconds: seconds)
                supersedeRequest(&s, actions: &actions)
                reopen(&s, now: now, budget: budget, actions: &actions)
            case let .studio(seconds):
                s.ledger.startStudio(seconds: seconds, now: now)
                supersedeRequest(&s, actions: &actions)
                reopen(&s, now: now, budget: budget, actions: &actions)
            case .lock:
                s.ledger.lockedByParent = true
                supersedeRequest(&s, actions: &actions)
                if s.phase != .locked {
                    lock(&s, now: now, actions: &actions)
                }
            case .unlock:
                s.ledger.lockedByParent = false
                reopen(&s, now: now, budget: budget, actions: &actions)
            }

        case .lockConfirmed:
            if s.phase == .locked {
                s.lockConfirmedAt = now
            }
        }

        return (s, actions)
    }

    private static func lock(_ s: inout PolicyState, now: Date, actions: inout [PolicyAction]) {
        s.phase = .locked
        s.graceUntil = nil
        s.lockSentAt = now
        s.lockConfirmedAt = nil
        actions.append(.lock)
    }

    /// Back to `open` when time is left (or a studio window runs) and no parent lock holds.
    /// Otherwise the phase does not change.
    private static func reopen(_ s: inout PolicyState, now: Date, budget: Int,
                               actions: inout [PolicyAction]) {
        guard !s.ledger.lockedByParent else { return }
        guard s.ledger.remaining(budget: budget) > 0 || s.ledger.inStudio(at: now) else { return }
        if s.phase == .locked {
            actions.append(.unlock)
        }
        s.phase = .open
        s.graceUntil = nil
        s.lockSentAt = nil
        s.lockConfirmedAt = nil
    }

    private static func supersedeRequest(_ s: inout PolicyState, actions: inout [PolicyAction]) {
        if let request = s.request {
            actions.append(.cancelRequest(requestID: request.id))
            s.request = nil
        }
    }
}
