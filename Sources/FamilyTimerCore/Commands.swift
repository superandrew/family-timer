import Foundation

public func parseDuration(_ text: String) -> Int? {
    let s = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if s.isEmpty || s.count > 6 { return nil }

    let isDigit = { (c: Character) in c.isASCII && c.isNumber }

    if s.allSatisfy(isDigit) {
        guard let minutes = Int(s) else { return nil }
        let seconds = minutes * 60
        return (60...43200).contains(seconds) ? seconds : nil
    }

    if s.hasSuffix("min") {
        let part = String(s.dropLast(3))
        guard !part.isEmpty, part.allSatisfy(isDigit), let minutes = Int(part) else { return nil }
        let seconds = minutes * 60
        return (60...43200).contains(seconds) ? seconds : nil
    }

    if s.hasSuffix("m") && !s.contains("h") {
        let part = String(s.dropLast(1))
        guard !part.isEmpty, part.allSatisfy(isDigit), let minutes = Int(part) else { return nil }
        let seconds = minutes * 60
        return (60...43200).contains(seconds) ? seconds : nil
    }

    if s.contains("h") {
        let parts = s.components(separatedBy: "h")
        guard parts.count == 2 else { return nil }
        let hoursPart = parts[0]
        let minutesPart = parts[1]

        guard !hoursPart.isEmpty, hoursPart.allSatisfy(isDigit), let hours = Int(hoursPart) else { return nil }

        var extraMinutes = 0
        if !minutesPart.isEmpty {
            if minutesPart.hasSuffix("m") {
                let mPart = String(minutesPart.dropLast(1))
                guard !mPart.isEmpty, mPart.allSatisfy(isDigit), let m = Int(mPart) else { return nil }
                extraMinutes = m
            } else if minutesPart.allSatisfy(isDigit) {
                extraMinutes = Int(minutesPart) ?? 0
            } else {
                return nil
            }
        }

        guard (0...59).contains(extraMinutes) else { return nil }
        let minutes = hours * 60 + extraMinutes
        let seconds = minutes * 60
        return (60...43200).contains(seconds) ? seconds : nil
    }

    return nil
}

public enum Command: Equatable {
    case status
    case extra(seconds: Int)
    case studio(seconds: Int)
    case minecraft(seconds: Int)
    case lock
    case unlock
    case help
    case apps(days: Int)
    case week
}

public enum CommandError: Error, Equatable {
    case unknown(String)
    case missingDuration(String)
    case invalidDuration(String)
}

/// Like `parseCommand`, plus the child the command names, if any: `/extra 30 art`,
/// `/extra art 30`, `/lock art`, `/status art`. The name is the word that is not the duration.
public func parseAddressedCommand(_ text: String) -> (result: Result<Command, CommandError>, target: String?) {
    let parts = text.split(whereSeparator: { $0.isWhitespace }).map { String($0) }
    guard let first = parts.first else { return (parseCommand(text), nil) }
    var word = first.lowercased()
    if let at = word.firstIndex(of: "@") { word = String(word[..<at]) }
    let rest = Array(parts.dropFirst())
    if word == "/extra" || word == "/studio" || word == "/minecraft" || word == "/mc" {
        guard rest.count >= 2 else { return (parseCommand(text), nil) }
        if parseDuration(rest[0]) == nil && parseDuration(rest[1]) != nil {
            return (parseCommand(first + " " + rest[1]), rest[0])
        }
        return (parseCommand(first + " " + rest[0]), rest[1])
    }
    return (parseCommand(first), rest.first)
}

public func parseCommand(_ text: String) -> Result<Command, CommandError> {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let parts = trimmed.split(whereSeparator: { $0.isWhitespace }).map { String($0) }
    if parts.isEmpty {
        return .failure(.unknown(""))
    }

    var word = parts[0].lowercased()
    if let atIndex = word.firstIndex(of: "@") {
        word = String(word[..<atIndex])
    }

    switch word {
    case "/status":
        return .success(.status)
    case "/lock":
        return .success(.lock)
    case "/unlock":
        return .success(.unlock)
    case "/help", "/start":
        return .success(.help)
    case "/app", "/apps":
        return .success(.apps(days: 7))
    case "/oggi", "/today":
        return .success(.apps(days: 1))
    case "/settimana", "/week":
        return .success(.week)
    case "/extra", "/studio", "/minecraft", "/mc":
        guard parts.count >= 2 else {
            return .failure(.missingDuration(word))
        }
        let durationText = parts[1]
        guard let seconds = parseDuration(durationText) else {
            return .failure(.invalidDuration(durationText))
        }
        if word == "/extra" {
            return .success(.extra(seconds: seconds))
        } else if word == "/studio" {
            return .success(.studio(seconds: seconds))
        } else {
            return .success(.minecraft(seconds: seconds))
        }
    default:
        return .failure(.unknown(word))
    }
}

/// A press on a request button: `approve:<id>`, `approve:<id>:<seconds>` or `deny:<id>`.
public struct AnswerData: Equatable {
    public var requestID: String
    public var approved: Bool
    public var seconds: Int?

    public init(requestID: String, approved: Bool, seconds: Int? = nil) {
        self.requestID = requestID
        self.approved = approved
        self.seconds = seconds
    }
}

public func parseAnswerData(_ data: String) -> AnswerData? {
    let parts = data.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
    guard parts.count == 2 || parts.count == 3, !parts[1].isEmpty else { return nil }
    guard parts[0] == "approve" || parts[0] == "deny" else { return nil }
    if parts.count == 2 {
        return AnswerData(requestID: parts[1], approved: parts[0] == "approve")
    }
    guard parts[0] == "approve", let seconds = Int(parts[2]), seconds > 0 else { return nil }
    return AnswerData(requestID: parts[1], approved: true, seconds: seconds)
}
