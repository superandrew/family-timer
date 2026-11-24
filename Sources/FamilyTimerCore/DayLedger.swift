import Foundation

public struct DayLedger: Codable, Equatable {
    public var day: String
    public var used: Int
    public var extra: Int
    public var studioUntil: Date?
    public var lockedByParent: Bool
    public var minecraftExtra: Int?
    /// Time requests sent today, and how they were answered.
    public var requests: Int?
    public var approved: Int?
    public var denied: Int?

    public init(day: String, used: Int = 0, extra: Int = 0,
                studioUntil: Date? = nil, lockedByParent: Bool = false,
                minecraftExtra: Int? = nil) {
        self.day = day
        self.used = used
        self.extra = extra
        self.studioUntil = studioUntil
        self.lockedByParent = lockedByParent
        self.minecraftExtra = minecraftExtra
    }

    public static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
    }

    public static func budget(for date: Date, config: Config, calendar: Calendar) -> Int {
        calendar.isDateInWeekend(date) ? config.weekendLimit : config.weekdayLimit
    }

    public static func minecraftBudget(for date: Date, config: Config, calendar: Calendar) -> Int {
        calendar.isDateInWeekend(date) ? config.weekendMinecraftLimit : config.minecraftLimit
    }

    public static func fresh(for date: Date, calendar: Calendar) -> DayLedger {
        DayLedger(day: dayKey(date, calendar: calendar))
    }

    public func rolled(to date: Date, calendar: Calendar) -> DayLedger {
        DayLedger.dayKey(date, calendar: calendar) == day ? self : DayLedger.fresh(for: date, calendar: calendar)
    }

    public func inStudio(at now: Date) -> Bool {
        guard let until = studioUntil else { return false }
        return now < until
    }

    public func remaining(budget: Int) -> Int {
        max(0, budget + extra - used)
    }

    public mutating func tick(seconds: Int, active: Bool, now: Date) {
        if active && !inStudio(at: now) {
            used += seconds
        }
    }

    public mutating func grantExtra(seconds: Int) {
        extra += seconds
    }

    public mutating func grantMinecraftExtra(seconds: Int) {
        minecraftExtra = (minecraftExtra ?? 0) + seconds
    }

    public mutating func countRequest() {
        requests = (requests ?? 0) + 1
    }

    public mutating func countAnswer(approved yes: Bool) {
        if yes {
            approved = (approved ?? 0) + 1
        } else {
            denied = (denied ?? 0) + 1
        }
    }

    public mutating func startStudio(seconds: Int, now: Date) {
        studioUntil = now.addingTimeInterval(TimeInterval(seconds))
    }
}
