import Foundation

public enum AgentWatchAction: Equatable {
    case restart
    case notifyMissing
    case notifyBack
}

public struct AgentWatch: Equatable {
    public static let wait: TimeInterval = 60
    public static let maxRestarts = 2

    public var missingSince: Date?
    public var lastRestart: Date?
    public var restarts: Int
    public var notified: Bool

    public init() {
        self.missingSince = nil
        self.lastRestart = nil
        self.restarts = 0
        self.notified = false
    }

    public mutating func check(now: Date, childAtConsole: Bool, agentConnected: Bool) -> AgentWatchAction? {
        if agentConnected {
            let wasNotified = notified
            missingSince = nil
            lastRestart = nil
            restarts = 0
            notified = false
            return wasNotified ? .notifyBack : nil
        }
        if !childAtConsole {
            missingSince = nil
            lastRestart = nil
            restarts = 0
            return nil
        }
        if missingSince == nil {
            missingSince = now
            return nil
        }
        let since = lastRestart ?? missingSince!
        if now.timeIntervalSince(since) < AgentWatch.wait {
            return nil
        }
        if restarts < AgentWatch.maxRestarts {
            restarts += 1
            lastRestart = now
            return .restart
        }
        if !notified {
            notified = true
            lastRestart = now
            return .notifyMissing
        }
        return nil
    }
}
