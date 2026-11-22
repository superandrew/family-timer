import XCTest
@testable import FamilyTimerCore

final class CommandsTests: XCTestCase {
    func testDurations() {
        XCTAssertEqual(parseDuration("30"), 30 * 60)
        XCTAssertEqual(parseDuration("30m"), 30 * 60)
        XCTAssertEqual(parseDuration("45min"), 45 * 60)
        XCTAssertEqual(parseDuration("2h"), 2 * 3600)
        XCTAssertEqual(parseDuration(" 2H "), 2 * 3600)
        XCTAssertEqual(parseDuration("1h30"), 90 * 60)
        XCTAssertEqual(parseDuration("1h30m"), 90 * 60)
        XCTAssertEqual(parseDuration("12h"), 12 * 3600)
        XCTAssertNil(parseDuration("0"))
        XCTAssertNil(parseDuration("13h"))
        XCTAssertNil(parseDuration("1h75"))
        XCTAssertNil(parseDuration("h"))
        XCTAssertNil(parseDuration("abc"))
        XCTAssertNil(parseDuration(""))
        XCTAssertNil(parseDuration("9999999"))
        XCTAssertNil(parseDuration("999999999999999999"))
    }

    func testCommands() {
        XCTAssertEqual(parseCommand("/status"), .success(.status))
        XCTAssertEqual(parseCommand("  /STATUS  "), .success(.status))
        XCTAssertEqual(parseCommand("/status@family_bot"), .success(.status))
        XCTAssertEqual(parseCommand("/extra 30"), .success(.extra(seconds: 30 * 60)))
        XCTAssertEqual(parseCommand("/extra@family_bot 1h"), .success(.extra(seconds: 3600)))
        XCTAssertEqual(parseCommand("/studio 2h please"), .success(.studio(seconds: 2 * 3600)))
        XCTAssertEqual(parseCommand("/extra\n30"), .success(.extra(seconds: 30 * 60)))
        XCTAssertEqual(parseCommand("/extra"), .failure(.missingDuration("/extra")))
        XCTAssertEqual(parseCommand("/studio xx"), .failure(.invalidDuration("xx")))
        XCTAssertEqual(parseCommand("/lock"), .success(.lock))
        XCTAssertEqual(parseCommand("/unlock"), .success(.unlock))
        XCTAssertEqual(parseCommand("/start"), .success(.help))
        XCTAssertEqual(parseCommand("/help"), .success(.help))
        XCTAssertEqual(parseCommand("ciao"), .failure(.unknown("ciao")))
        XCTAssertEqual(parseCommand("/foo bar"), .failure(.unknown("/foo")))
        XCTAssertEqual(parseCommand(""), .failure(.unknown("")))
    }
}
