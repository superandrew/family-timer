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

/// The agent's report of what is in front (SPEC 9), sent every 10 s and at every app
/// switch. `accessibility`: whether the agent may read the browser's address.
public struct AgentReport: Codable, Equatable {
    public var frontmost: Frontmost?
    public var accessibility: Bool

    public init(frontmost: Frontmost?, accessibility: Bool) {
        self.frontmost = frontmost
        self.accessibility = accessibility
    }
}

/// "Ask for more time" with what the child wrote (optional). Sent instead of the bare
/// `request_time` message; the daemon cleans the text with `Replies.cleanReason`.
public struct TimeRequest: Codable, Equatable {
    public var requestTime: Bool
    public var reason: String?

    public init(reason: String? = nil) {
        self.requestTime = true
        self.reason = reason
    }

    enum CodingKeys: String, CodingKey {
        case requestTime = "request_time"
        case reason
    }
}

public enum DaemonMessageType: String, Codable, Equatable {
    case state
    case showExpiredDialog = "show_expired_dialog"
    case requestResult = "request_result"
    case lock
    case unlock
    case close
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
    /// `state`: what the child can do about more time.
    public var askState: AskState?
    /// `state`: Minecraft seconds left today, nil = no limit.
    public var minecraftRemaining: Int?
    /// `close`: usage key of the app to close.
    public var app: String?
    /// `close`.
    public var reason: BlockReason?
    /// `state`: lines of the menu.
    public var menu: [String]?

    public init(type: DaemonMessageType, remaining: Int? = nil, phase: Phase? = nil,
                graceRemaining: Int? = nil, dryRun: Bool? = nil, language: Language? = nil,
                approved: Bool? = nil, askState: AskState? = nil,
                minecraftRemaining: Int? = nil, app: String? = nil, reason: BlockReason? = nil,
                menu: [String]? = nil) {
        self.type = type
        self.remaining = remaining
        self.phase = phase
        self.graceRemaining = graceRemaining
        self.dryRun = dryRun
        self.language = language
        self.approved = approved
        self.askState = askState
        self.minecraftRemaining = minecraftRemaining
        self.app = app
        self.reason = reason
        self.menu = menu
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
