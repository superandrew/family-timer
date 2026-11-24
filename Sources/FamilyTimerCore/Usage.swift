import Foundation

public enum UsageCategory: String, Codable, CaseIterable, Equatable {
    case games
    case study
    case video
    case coding
    case other
}

/// What the agent reports: the frontmost app and, for a browser, the page.
public struct Frontmost: Codable, Equatable {
    public var bundleID: String
    public var name: String
    public var url: String?
    public var title: String?

    public init(bundleID: String, name: String, url: String? = nil, title: String? = nil) {
        self.bundleID = bundleID
        self.name = name
        self.url = url
        self.title = title
    }
}

public struct UsageEntry: Equatable {
    public var key: String
    public var name: String
    public var seconds: Int

    public init(key: String, name: String, seconds: Int) {
        self.key = key
        self.name = name
        self.seconds = seconds
    }
}

public struct DayUsage: Codable, Equatable {
    public var day: String
    public var seconds: [String: Int]

    public init(day: String, seconds: [String: Int] = [:]) {
        self.day = day
        self.seconds = seconds
    }
}

public struct UsageLog: Codable, Equatable {
    public static let keepDays = 35

    /// Oldest first, at most `keepDays`.
    public var days: [DayUsage]
    /// Key -> name to show (app name, or the site's host).
    public var names: [String: String]
    /// Key -> category chosen by a parent.
    public var categories: [String: UsageCategory]

    public init() {
        self.days = []
        self.names = [:]
        self.categories = [:]
    }

    public static func appKey(_ bundleID: String) -> String {
        return "app:" + bundleID
    }

    public static func siteKey(url: String) -> String? {
        var text = url
        // Trim spaces and newlines
        let toTrim = CharacterSet(charactersIn: " \n\r\t")
        text = text.trimmingCharacters(in: toTrim)

        if !text.contains("://") {
            text = "https://" + text
        }

        guard let u = URL(string: text) else { return nil }
        guard let scheme = u.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return nil
        }
        guard let host = u.host, !host.isEmpty else { return nil }

        var h = host.lowercased()
        if h.hasPrefix("www.") {
            h = String(h.dropFirst(4))
        }
        return "site:" + h
    }

    public static func isSite(_ key: String) -> Bool {
        return key.hasPrefix("site:")
    }

    /// Bundle ids of the browsers whose page the agent reads.
    public static let browsers: Set<String> = [
        "com.apple.Safari", "com.apple.SafariTechnologyPreview", "com.google.Chrome",
        "org.mozilla.firefox", "com.microsoft.edgemac", "com.brave.Browser",
        "company.thebrowser.Browser", "com.operasoftware.Opera", "com.vivaldi.Vivaldi",
    ]

    /// True for the app key of a browser ("app:com.google.Chrome").
    public static func isBrowser(_ key: String) -> Bool {
        guard key.hasPrefix("app:") else { return false }
        let bundleID = String(key.dropFirst(4))
        return browsers.contains(bundleID)
    }

    /// True when the parents should be asked to classify `key`: not a browser, not classified yet.
    public func needsCategory(_ key: String) -> Bool {
        return !UsageLog.isBrowser(key) && categories[key] == nil
    }

    public mutating func add(_ frontmost: Frontmost, seconds: Int, day: String) {
        if seconds <= 0 { return }

        var idx: Int?
        if let foundIdx = days.firstIndex(where: { $0.day == day }) {
            idx = foundIdx
        } else {
            days.append(DayUsage(day: day))
            days.sort { $0.day < $1.day }
            idx = days.firstIndex(where: { $0.day == day })
        }

        guard let i = idx else { return }

        let appKey = UsageLog.appKey(frontmost.bundleID)
        days[i].seconds[appKey, default: 0] += seconds
        names[appKey] = frontmost.name

        if let url = frontmost.url, let siteKey = UsageLog.siteKey(url: url) {
            days[i].seconds[siteKey, default: 0] += seconds
            let host = String(siteKey.dropFirst(5))
            names[siteKey] = host
        }

        while days.count > UsageLog.keepDays {
            days.removeFirst()
        }
    }

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

    public func entries(from firstDay: String, to lastDay: String) -> [UsageEntry] {
        var totals: [String: Int] = [:]
        for day in days {
            if firstDay <= day.day && day.day <= lastDay {
                for (key, sec) in day.seconds {
                    totals[key, default: 0] += sec
                }
            }
        }

        var result: [UsageEntry] = []
        for (key, sec) in totals {
            let name = names[key] ?? key
            result.append(UsageEntry(key: key, name: name, seconds: sec))
        }

        result.sort {
            if $0.seconds != $1.seconds {
                return $0.seconds > $1.seconds
            }
            return $0.key < $1.key
        }
        return result
    }

    public func total(for key: String) -> Int {
        var total = 0
        for day in days {
            total += day.seconds[key] ?? 0
        }
        return total
    }
}
