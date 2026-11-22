import XCTest
@testable import FamilyTimerCore

final class AgentProtocolTests: XCTestCase {
    func testDaemonMessageWire() {
        let message = DaemonMessage(type: .state, remaining: 300, phase: .open, dryRun: true)
        XCTAssertEqual(String(decoding: Wire.encode(message), as: UTF8.self),
                       "{\"dryRun\":true,\"phase\":\"open\",\"remaining\":300,\"type\":\"state\"}\n")
        XCTAssertEqual(try JSONDecoder().decode(DaemonMessage.self, from: Wire.encode(message)), message)
    }

    func testAgentMessageWire() {
        XCTAssertEqual(String(decoding: Wire.encode(AgentMessage.requestTime), as: UTF8.self),
                       "\"request_time\"\n")
        XCTAssertEqual(try JSONDecoder().decode(AgentMessage.self, from: Data("\"locked\"".utf8)), .locked)
    }

    func testFromAction() {
        XCTAssertEqual(DaemonMessage.from(.lock), DaemonMessage(type: .lock))
        XCTAssertEqual(DaemonMessage.from(.requestResult(requestID: "r", approved: true)),
                       DaemonMessage(type: .requestResult, approved: true))
        XCTAssertNil(DaemonMessage.from(.logout))
        XCTAssertNil(DaemonMessage.from(.sendTimeRequest(requestID: "r", seconds: 60)))
    }

    func testLineBuffer() {
        var buffer = LineBuffer(maxLine: 5)
        XCTAssertEqual(buffer.append(Data("ab".utf8)), [])
        XCTAssertEqual(buffer.append(Data("c\n\nde\nf".utf8)), [Data("abc".utf8), Data("de".utf8)])
        XCTAssertEqual(buffer.append(Data("ghijkl\nmn\n".utf8)), [Data("mn".utf8)])
    }
}

final class AgentTextsTests: XCTestCase {
    func testMenuTitle() {
        XCTAssertEqual(AgentTexts.menuTitle(remaining: 2700, phase: .open, graceRemaining: nil, .it), "⏱ 45m")
        XCTAssertEqual(AgentTexts.menuTitle(remaining: 61, phase: .open, graceRemaining: nil, .en), "⏱ 2m")
        XCTAssertEqual(AgentTexts.menuTitle(remaining: 0, phase: .grace, graceRemaining: 240, .it),
                       "⏱ tempo finito (4m)")
        XCTAssertEqual(AgentTexts.menuTitle(remaining: 0, phase: .locked, graceRemaining: nil, .en), "⏱ locked")
    }

    func testDialogs() {
        XCTAssertEqual(AgentTexts.warning(minutes: 5, .it), "Mancano 5 minuti per oggi.")
        XCTAssertEqual(AgentTexts.warning(minutes: 1, .en), "1 minute left today. Save your work.")
        XCTAssertEqual(AgentTexts.expired(graceRemaining: 300, .it),
                       "Il tempo di oggi è finito. Lo schermo si blocca tra 5m.\nPuoi chiedere altro tempo ai genitori.")
    }
}
