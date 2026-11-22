import XCTest
@testable import FamilyTimerCore

final class UsageTests: XCTestCase {
    func testSiteKey() {
        XCTAssertEqual(UsageLog.siteKey(url: "https://www.YouTube.com/watch?v=1"), "site:youtube.com")
        XCTAssertEqual(UsageLog.siteKey(url: "classroom.google.com/c/123"), "site:classroom.google.com")
        XCTAssertEqual(UsageLog.siteKey(url: "  http://poki.com  "), "site:poki.com")
        XCTAssertNil(UsageLog.siteKey(url: "file:///Users/a/x.html"))
        XCTAssertNil(UsageLog.siteKey(url: "about:blank"))
        XCTAssertNil(UsageLog.siteKey(url: "minecraft mods"))
        XCTAssertNil(UsageLog.siteKey(url: ""))
    }

    func testAppKeyAndIsSite() {
        XCTAssertEqual(UsageLog.appKey("com.mojang.minecraft"), "app:com.mojang.minecraft")
        XCTAssertTrue(UsageLog.isSite("site:a.com"))
        XCTAssertFalse(UsageLog.isSite("app:a"))
    }

    func testAddAndEntries() {
        var log = UsageLog()
        let safari = Frontmost(bundleID: "com.apple.Safari", name: "Safari", url: "https://www.youtube.com/x")
        log.add(safari, seconds: 15, day: "2026-11-22")
        log.add(safari, seconds: 15, day: "2026-11-22")
        let minecraft = Frontmost(bundleID: "com.mojang.minecraft", name: "Minecraft")
        log.add(minecraft, seconds: 15, day: "2026-11-22")

        let entries = log.entries(from: "2026-11-22", to: "2026-11-22")
        XCTAssertEqual(entries, [
            UsageEntry(key: "app:com.apple.Safari", name: "Safari", seconds: 30),
            UsageEntry(key: "site:youtube.com", name: "youtube.com", seconds: 30),
            UsageEntry(key: "app:com.mojang.minecraft", name: "Minecraft", seconds: 15)
        ])
    }

    func testDaysSortingAndTotals() {
        var log = UsageLog()
        let minecraft = Frontmost(bundleID: "com.mojang.minecraft", name: "Minecraft")
        log.add(minecraft, seconds: 15, day: "2026-11-21")
        log.add(minecraft, seconds: 30, day: "2026-11-22")
        log.add(minecraft, seconds: 45, day: "2026-11-20")

        XCTAssertEqual(log.days.map(\.day), ["2026-11-20", "2026-11-21", "2026-11-22"])

        let entries = log.entries(from: "2026-11-21", to: "2026-11-22")
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.seconds, 45)

        XCTAssertEqual(log.total(for: "app:com.mojang.minecraft"), 90)
    }

    func testKeepDays() {
        var log = UsageLog()
        let minecraft = Frontmost(bundleID: "com.mojang.minecraft", name: "Minecraft")
        // 2026-10-01 to 2026-11-09
        // Oct: 31 days, Nov: 9 days. Total 40 days.
        let cal = Calendar(identifier: .gregorian)
        var date = DateComponents(calendar: cal, year: 2026, month: 10, day: 1).date!
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        for _ in 0..<40 {
            let dayStr = formatter.string(from: date)
            log.add(minecraft, seconds: 15, day: dayStr)
            date = cal.date(byAdding: .day, value: 1, to: date)!
        }

        XCTAssertEqual(log.days.count, 35)
        XCTAssertEqual(log.days.first?.day, "2026-10-06")
    }

    func testZeroSeconds() {
        var log = UsageLog()
        let safari = Frontmost(bundleID: "com.apple.Safari", name: "Safari")
        log.add(safari, seconds: 0, day: "2026-11-22")
        XCTAssertEqual(log, UsageLog())
    }

    func testInvalidUrlCountsAppOnly() {
        var log = UsageLog()
        let safari = Frontmost(bundleID: "com.apple.Safari", name: "Safari", url: "about:blank")
        log.add(safari, seconds: 15, day: "2026-11-22")
        let entries = log.entries(from: "2026-11-22", to: "2026-11-22")
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.key, "app:com.apple.Safari")
    }

    func testJsonRoundTrip() {
        var log = UsageLog()
        let minecraft = Frontmost(bundleID: "com.mojang.minecraft", name: "Minecraft")
        log.add(minecraft, seconds: 15, day: "2026-11-22")
        log.categories["app:com.mojang.minecraft"] = .games

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try! encoder.encode(log)
        let decoded = try! decoder.decode(UsageLog.self, from: data)
        XCTAssertEqual(log, decoded)
    }
}
