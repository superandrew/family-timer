import Foundation

public enum ConfigError: Error, Equatable {
    case missing(String)
    case invalidNumber(key: String, value: String)
    case invalidValue(key: String, value: String)
}

/// Language of every text the child and the parents see.
public enum Language: String, Codable, Equatable {
    case en
    case it
}

public struct Config: Equatable {
    public var childUser: String
    public var weekdayLimit: Int
    public var weekendLimit: Int
    public var extensionTime: Int
    public var idleThreshold: Int
    public var graceTime: Int
    public var approvalTimeout: Int
    public var telegramBotToken: String
    public var telegramChatID: String
    public var parentUserIDs: [Int64]
    public var healthcheckURL: String
    public var healthcheckInterval: Int
    public var language: Language

    public init(
        childUser: String,
        weekdayLimit: Int = 3600,
        weekendLimit: Int = 3600,
        extensionTime: Int = 1800,
        idleThreshold: Int = 120,
        graceTime: Int = 300,
        approvalTimeout: Int = 600,
        telegramBotToken: String = "",
        telegramChatID: String = "",
        parentUserIDs: [Int64] = [],
        healthcheckURL: String = "",
        healthcheckInterval: Int = 300,
        language: Language = .en
    ) {
        self.childUser = childUser
        self.weekdayLimit = weekdayLimit
        self.weekendLimit = weekendLimit
        self.extensionTime = extensionTime
        self.idleThreshold = idleThreshold
        self.graceTime = graceTime
        self.approvalTimeout = approvalTimeout
        self.telegramBotToken = telegramBotToken
        self.telegramChatID = telegramChatID
        self.parentUserIDs = parentUserIDs
        self.healthcheckURL = healthcheckURL
        self.healthcheckInterval = healthcheckInterval
        self.language = language
    }

    public static func parse(_ text: String) throws -> Config {
        var childUser: String?
        var weekdayLimit = 3600
        var weekendLimit = 3600
        var extensionTime = 1800
        var idleThreshold = 120
        var graceTime = 300
        var approvalTimeout = 600
        var telegramBotToken = ""
        var telegramChatID = ""
        var parentUserIDs: [Int64] = []
        var healthcheckURL = ""
        var healthcheckInterval = 300
        var language = Language.en

        let lines = text.components(separatedBy: "\n")
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: CharacterSet(charactersIn: " \t"))
            if line.isEmpty || line.hasPrefix("#") {
                continue
            }
            guard let eqIndex = line.firstIndex(of: "=") else {
                continue
            }
            let key = line[..<eqIndex].trimmingCharacters(in: CharacterSet(charactersIn: " \t"))
            var value = line[line.index(after: eqIndex)...].trimmingCharacters(in: CharacterSet(charactersIn: " \t"))
            if value.count >= 2 {
                let first = value.first
                let last = value.last
                if (first == "\"" && last == "\"") || (first == "'" && last == "'") {
                    value = String(value.dropFirst().dropLast())
                }
            }

            switch key {
            case "CHILD_USER":
                childUser = value
            case "TIME_LIMIT":
                guard let v = Int(value), v > 0 else {
                    throw ConfigError.invalidNumber(key: key, value: value)
                }
                weekdayLimit = v
            case "WEEKEND_TIME_LIMIT":
                guard let v = Int(value), v > 0 else {
                    throw ConfigError.invalidNumber(key: key, value: value)
                }
                weekendLimit = v
            case "EXTENSION_TIME":
                guard let v = Int(value), v > 0 else {
                    throw ConfigError.invalidNumber(key: key, value: value)
                }
                extensionTime = v
            case "IDLE_THRESHOLD":
                guard let v = Int(value), v > 0 else {
                    throw ConfigError.invalidNumber(key: key, value: value)
                }
                idleThreshold = v
            case "GRACE_TIME":
                guard let v = Int(value), v > 0 else {
                    throw ConfigError.invalidNumber(key: key, value: value)
                }
                graceTime = v
            case "APPROVAL_TIMEOUT":
                guard let v = Int(value), v > 0 else {
                    throw ConfigError.invalidNumber(key: key, value: value)
                }
                approvalTimeout = v
            case "TELEGRAM_BOT_TOKEN":
                telegramBotToken = value
            case "TELEGRAM_CHAT_ID":
                telegramChatID = value
            case "PARENT_USER_IDS":
                if value.isEmpty {
                    parentUserIDs = []
                } else {
                    let parts = value.components(separatedBy: ",")
                    var ids: [Int64] = []
                    for part in parts {
                        let trimmed = part.trimmingCharacters(in: CharacterSet(charactersIn: " \t"))
                        guard let id = Int64(trimmed) else {
                            throw ConfigError.invalidNumber(key: "PARENT_USER_IDS", value: trimmed)
                        }
                        ids.append(id)
                    }
                    parentUserIDs = ids
                }
            case "HEALTHCHECK_URL":
                healthcheckURL = value
            case "HEALTHCHECK_INTERVAL":
                guard let v = Int(value), v > 0 else {
                    throw ConfigError.invalidNumber(key: key, value: value)
                }
                healthcheckInterval = v
            case "LANGUAGE":
                guard let v = Language(rawValue: value.lowercased()) else {
                    throw ConfigError.invalidValue(key: key, value: value)
                }
                language = v
            default:
                break
            }
        }

        guard let cu = childUser, !cu.isEmpty else {
            throw ConfigError.missing("CHILD_USER")
        }

        return Config(
            childUser: cu,
            weekdayLimit: weekdayLimit,
            weekendLimit: weekendLimit,
            extensionTime: extensionTime,
            idleThreshold: idleThreshold,
            graceTime: graceTime,
            approvalTimeout: approvalTimeout,
            telegramBotToken: telegramBotToken,
            telegramChatID: telegramChatID,
            parentUserIDs: parentUserIDs,
            healthcheckURL: healthcheckURL,
            healthcheckInterval: healthcheckInterval,
            language: language
        )
    }
}
