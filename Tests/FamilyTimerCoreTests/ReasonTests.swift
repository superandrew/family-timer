import XCTest
@testable import FamilyTimerCore

final class ReasonTests: XCTestCase {
    func testClean() {
        XCTAssertEqual(Replies.cleanReason(nil), nil)
        XCTAssertEqual(Replies.cleanReason(""), nil)
        XCTAssertEqual(Replies.cleanReason("  \n "), nil)
        XCTAssertEqual(Replies.cleanReason("  finire\n\ni compiti  "), "finire i compiti")
        XCTAssertEqual(Replies.cleanReason("a\tb\u{7}c"), "a b c")
        let long = String(repeating: "x", count: 130)
        XCTAssertEqual(Replies.cleanReason(long), String(repeating: "x", count: 119) + "…")
        XCTAssertEqual(Replies.cleanReason(String(repeating: "y", count: 120)), String(repeating: "y", count: 120))
    }

    func testRequestText() {
        XCTAssertEqual(Replies.request(child: "Art", seconds: 1800, reason: "compiti", .it),
                       "⏰ Art ha finito il tempo di oggi e chiede altri 30m.\n📝 Cosa deve fare: compiti")
        XCTAssertEqual(Replies.request(child: "Art", seconds: 1800, remaining: 600, reason: "homework", .en),
                       "⏰ Art has 10m left and asks for 30m more.\n📝 What for: homework")
        XCTAssertEqual(Replies.request(child: "Art", seconds: 1800, .it),
                       "⏰ Art ha finito il tempo di oggi e chiede altri 30m.")
    }

    func testWire() throws {
        let data = Wire.encode(TimeRequest(reason: "compiti"))
        XCTAssertEqual(String(data: data, encoding: .utf8), "{\"reason\":\"compiti\",\"request_time\":true}\n")

        let decoded = try JSONDecoder().decode(TimeRequest.self, from: Data("{\"request_time\":true}".utf8))
        XCTAssertEqual(decoded, TimeRequest())

        XCTAssertThrowsError(try JSONDecoder().decode(TimeRequest.self, from: Data("{\"accessibility\":true}".utf8)))

        XCTAssertThrowsError(try JSONDecoder().decode(AgentReport.self, from: Data("{\"reason\":\"x\",\"request_time\":true}".utf8)))
    }

    func testTexts() {
        XCTAssertEqual(AgentTexts.sendButton(.it), "Invia")
        XCTAssertEqual(AgentTexts.cancelButton(.it), "Annulla")
        XCTAssertEqual(AgentTexts.reasonPrompt(.it), "Chiedi altro tempo.\nCosa devi fare? (facoltativo)")
    }
}
