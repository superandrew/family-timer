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
    case lock
    case unlock
    case help
}

public enum CommandError: Error, Equatable {
    case unknown(String)
    case missingDuration(String)
    case invalidDuration(String)
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
    case "/extra", "/studio":
        guard parts.count >= 2 else {
            return .failure(.missingDuration(word))
        }
        let durationText = parts[1]
        guard let seconds = parseDuration(durationText) else {
            return .failure(.invalidDuration(durationText))
        }
        if word == "/extra" {
            return .success(.extra(seconds: seconds))
        } else {
            return .success(.studio(seconds: seconds))
        }
    default:
        return .failure(.unknown(word))
    }
}
