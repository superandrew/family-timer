import Foundation

/// One day that ended (SPEC 6): kept to build the weekly report.
public struct DaySummary: Codable, Equatable {
    public var day: String
    public var used: Int
    public var extra: Int
    public var minecraft: Int
    public var requests: Int
    public var approved: Int
    public var denied: Int

    public init(day: String, used: Int = 0, extra: Int = 0, minecraft: Int = 0,
                requests: Int = 0, approved: Int = 0, denied: Int = 0) {
        self.day = day
        self.used = used
        self.extra = extra
        self.minecraft = minecraft
        self.requests = requests
        self.approved = approved
        self.denied = denied
    }

    /// `minecraft`: Minecraft seconds of that day, from the usage log.
    public static func from(_ ledger: DayLedger, minecraft: Int) -> DaySummary {
        DaySummary(day: ledger.day, used: ledger.used, extra: ledger.extra, minecraft: minecraft,
                   requests: ledger.requests ?? 0, approved: ledger.approved ?? 0,
                   denied: ledger.denied ?? 0)
    }
}

public struct History: Codable, Equatable {
    public static let keepDays = 35
    /// Oldest first.
    public var days: [DaySummary]
    /// The day key of the last weekly report sent.
    public var lastReport: String?

    public init(days: [DaySummary] = [], lastReport: String? = nil) {
        self.days = days
        self.lastReport = lastReport
    }

    /// Adds or replaces the summary of that day; keeps the days sorted and at most `keepDays`.
    public mutating func record(_ summary: DaySummary) {
        days.removeAll { $0.day == summary.day }
        days.append(summary)
        days.sort { $0.day < $1.day }
        if days.count > History.keepDays {
            days.removeFirst(days.count - History.keepDays)
        }
    }

    /// The 7 days ending with `today` (oldest first). A day not in the history is
    /// `today` itself when it matches `todaySummary.day`, otherwise an empty summary.
    public func week(ending todaySummary: DaySummary, calendar: Calendar) -> [DaySummary] {
        var result: [DaySummary] = []
        guard let end = History.date(todaySummary.day, calendar: calendar) else { return [todaySummary] }
        for back in (0..<7).reversed() {
            let date = calendar.date(byAdding: .day, value: -back, to: end)!
            let key = DayLedger.dayKey(date, calendar: calendar)
            if key == todaySummary.day {
                result.append(todaySummary)
            } else {
                result.append(days.first { $0.day == key } ?? DaySummary(day: key))
            }
        }
        return result
    }

    /// `"2026-11-23"` -> noon of that day in the calendar's time zone.
    public static func date(_ key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }
}
