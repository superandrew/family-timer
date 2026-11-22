import XCTest
@testable import FamilyTimerCore

final class AgentWatchTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    func run(_ w: inout AgentWatch, _ s: TimeInterval, console: Bool = true, connected: Bool = false) -> AgentWatchAction? {
        w.check(now: t0 + s, childAtConsole: console, agentConnected: connected)
    }

    func testMissingAgentRestartsThenNotifies() {
        var w = AgentWatch()
        XCTAssertEqual(run(&w, 0), nil)
        XCTAssertEqual(run(&w, 15), nil)
        XCTAssertEqual(run(&w, 60), .restart)
        XCTAssertEqual(run(&w, 75), nil)
        XCTAssertEqual(run(&w, 120), .restart)
        XCTAssertEqual(run(&w, 180), .notifyMissing)
        XCTAssertEqual(run(&w, 240), nil)
        XCTAssertEqual(run(&w, 600), nil)
        XCTAssertEqual(w.restarts, 2)
        XCTAssertTrue(w.notified)
    }

    func testAgentConnectedResetsState() {
        var w = AgentWatch()
        XCTAssertEqual(run(&w, 0, connected: true), nil)
        XCTAssertEqual(run(&w, 60, connected: true), nil)
        XCTAssertNil(w.missingSince)
    }

    func testConnectedResetsThenMissingAgain() {
        var w = AgentWatch()
        XCTAssertEqual(run(&w, 0), nil)
        XCTAssertEqual(run(&w, 60), .restart)
        XCTAssertEqual(run(&w, 70, connected: true), nil)
        XCTAssertEqual(w.restarts, 0)
        XCTAssertEqual(run(&w, 80), nil)
        XCTAssertEqual(run(&w, 139), nil)
        XCTAssertEqual(run(&w, 140), .restart)
    }

    func testNotifyBackWhenConnectedAfterNotifyMissing() {
        var w = AgentWatch()
        XCTAssertEqual(run(&w, 0), nil)
        XCTAssertEqual(run(&w, 15), nil)
        XCTAssertEqual(run(&w, 60), .restart)
        XCTAssertEqual(run(&w, 75), nil)
        XCTAssertEqual(run(&w, 120), .restart)
        XCTAssertEqual(run(&w, 180), .notifyMissing)
        XCTAssertEqual(run(&w, 200, connected: true), .notifyBack)
        XCTAssertFalse(w.notified)
        XCTAssertEqual(run(&w, 215, connected: true), nil)
    }

    func testChildNotAtConsoleResetsState() {
        var w = AgentWatch()
        XCTAssertEqual(run(&w, 0, console: false), nil)
        XCTAssertEqual(run(&w, 60, console: false), nil)
        XCTAssertEqual(run(&w, 120, console: false), nil)
        XCTAssertEqual(run(&w, 180, console: false), nil)
        XCTAssertNil(w.missingSince)
    }

    func testConsoleFalseResetsThenBackAtConsole() {
        var w = AgentWatch()
        XCTAssertEqual(run(&w, 0), nil)
        XCTAssertEqual(run(&w, 60), .restart)
        XCTAssertEqual(run(&w, 70, console: false), nil)
        XCTAssertEqual(w.restarts, 0)
        XCTAssertEqual(run(&w, 80), nil)
        XCTAssertEqual(run(&w, 140), .restart)
    }

    func testNotifyMissingThenConsoleFalseThenBack() {
        var w = AgentWatch()
        XCTAssertEqual(run(&w, 0), nil)
        XCTAssertEqual(run(&w, 15), nil)
        XCTAssertEqual(run(&w, 60), .restart)
        XCTAssertEqual(run(&w, 75), nil)
        XCTAssertEqual(run(&w, 120), .restart)
        XCTAssertEqual(run(&w, 180), .notifyMissing)
        XCTAssertEqual(run(&w, 200, console: false), nil)
        XCTAssertTrue(w.notified)
        XCTAssertEqual(run(&w, 210), nil)
        XCTAssertEqual(run(&w, 270), .restart)
        XCTAssertEqual(run(&w, 330), .restart)
        XCTAssertEqual(run(&w, 390), nil)
    }
}
