import Foundation

// Daemon <-> agent messages (SPEC 3.3): one JSON object per line on a Unix socket.
// The daemon identifies the agent's user with the socket peer credentials, never with
// anything the agent writes.

public enum AgentMessage: String, Codable, Equatable {
    case hello
    case heartbeat
    case requestTime = "request_time"
    /// The screen is locked (sent at every check while the phase is `locked`).
    case locked
}

public enum DaemonMessageType: String, Codable, Equatable {
    case state
    case showExpiredDialog = "show_expired_dialog"
    case requestResult = "request_result"
    case lock
    case unlock
}

public struct DaemonMessage: Codable, Equatable {
    public var type: DaemonMessageType
    /// `state`: seconds left today, the phase, seconds left of grace, dry run, language.
    public var remaining: Int?
    public var phase: Phase?
    public var graceRemaining: Int?
    public var dryRun: Bool?
    public var language: Language?
    /// `request_result`.
    public var approved: Bool?

    public init(type: DaemonMessageType, remaining: Int? = nil, phase: Phase? = nil,
                graceRemaining: Int? = nil, dryRun: Bool? = nil, language: Language? = nil,
                approved: Bool? = nil) {
        self.type = type
        self.remaining = remaining
        self.phase = phase
        self.graceRemaining = graceRemaining
        self.dryRun = dryRun
        self.language = language
        self.approved = approved
    }

    /// The message for a policy action, or nil when the action is not for the agent.
    public static func from(_ action: PolicyAction) -> DaemonMessage? {
        switch action {
        case .showExpiredDialog: return DaemonMessage(type: .showExpiredDialog)
        case let .requestResult(_, approved): return DaemonMessage(type: .requestResult, approved: approved)
        case .lock: return DaemonMessage(type: .lock)
        case .unlock: return DaemonMessage(type: .unlock)
        case .sendTimeRequest, .cancelRequest, .logout: return nil
        }
    }
}

/// JSON line encoding.
public enum Wire {
    public static func encode<T: Encodable>(_ value: T) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        var data = (try? encoder.encode(value)) ?? Data()
        data.append(0x0A)
        return data
    }
}

/// Splits a byte stream into lines. A line longer than `maxLine` is dropped whole, so a
/// misbehaving peer cannot grow the buffer without limit.
public struct LineBuffer {
    public let maxLine: Int
    private var buffer = Data()
    private var discarding = false

    public init(maxLine: Int = 4096) {
        self.maxLine = maxLine
    }

    public mutating func append(_ data: Data) -> [Data] {
        var lines: [Data] = []
        for byte in data {
            if byte == 0x0A {
                if !discarding && !buffer.isEmpty { lines.append(buffer) }
                buffer.removeAll(keepingCapacity: true)
                discarding = false
            } else if !discarding {
                buffer.append(byte)
                if buffer.count > maxLine {
                    buffer.removeAll(keepingCapacity: true)
                    discarding = true
                }
            }
        }
        return lines
    }
}
