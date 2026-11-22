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

    func testAddressedCommands() {
        func check(_ text: String, _ result: Result<Command, CommandError>, _ target: String?,
                   line: UInt = #line) {
            let parsed = parseAddressedCommand(text)
            XCTAssertEqual(parsed.result, result, line: line)
            XCTAssertEqual(parsed.target, target, line: line)
        }
        check("/extra 5m art", .success(.extra(seconds: 5 * 60)), "art")
        check("/extra art 5m", .success(.extra(seconds: 5 * 60)), "art")
        check("/studio 2h bea", .success(.studio(seconds: 2 * 3600)), "bea")
        check("/extra@family_bot 30 Art", .success(.extra(seconds: 30 * 60)), "Art")
        check("/extra 30", .success(.extra(seconds: 30 * 60)), nil)
        check("/extra art", .failure(.invalidDuration("art")), nil)
        check("/extra xx art", .failure(.invalidDuration("xx")), "art")
        check("/lock bea", .success(.lock), "bea")
        check("/unlock", .success(.unlock), nil)
        check("/status art", .success(.status), "art")
        check("/foo art", .failure(.unknown("/foo")), "art")
        check("", .failure(.unknown("")), nil)
    }

    func testAppsCommands() {
        XCTAssertEqual(parseCommand("/app"), .success(.apps(days: 7)))
        XCTAssertEqual(parseCommand("/APPS"), .success(.apps(days: 7)))
        XCTAssertEqual(parseCommand("/oggi"), .success(.apps(days: 1)))
        XCTAssertEqual(parseCommand("/today@bot"), .success(.apps(days: 1)))
        let parsed = parseAddressedCommand("/app bea")
        XCTAssertEqual(parsed.result, .success(.apps(days: 7)))
        XCTAssertEqual(parsed.target, "bea")
    }
}
