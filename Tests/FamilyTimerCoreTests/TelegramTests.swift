import XCTest
@testable import FamilyTimerCore

final class TelegramTests: XCTestCase {
    func testDecodeUpdatesMessageAndCallback() {
        let json = """
        {"ok": true, "description": "...", "result": [
          {"update_id": 1, "message": {"from": {"id": 11}, "chat": {"id": -100}, "text": "/status"}},
          {"update_id": 2, "callback_query": {"id": "cb1", "from": {"id": 11},
                                              "message": {"chat": {"id": -100}}, "data": "approve:r1"}}
        ]}
        """
        let data = Data(json.utf8)
        let updates = try! decodeUpdates(data)
        XCTAssertEqual(updates.count, 2)
        XCTAssertEqual(updates[0], TelegramUpdate(updateID: 1, event: .message(chatID: -100, fromID: 11, text: "/status")))
        XCTAssertEqual(updates[1], TelegramUpdate(updateID: 2, event: .callback(id: "cb1", chatID: -100, fromID: 11, data: "approve:r1")))
    }

    func testDecodeUpdatesOther() {
        let json = """
        {"ok": true, "result": [{"update_id": 7, "message": {"from": {"id": 1}, "chat": {"id": 2}, "photo": []}}]}
        """
        let data = Data(json.utf8)
        let updates = try! decodeUpdates(data)
        XCTAssertEqual(updates.count, 1)
        XCTAssertEqual(updates[0].updateID, 7)
        XCTAssertEqual(updates[0].event, .other)
    }

    func testDecodeUpdatesEmpty() {
        let json = """
        {"ok": true, "result": []}
        """
        let data = Data(json.utf8)
        let updates = try! decodeUpdates(data)
        XCTAssertEqual(updates, [])
        XCTAssertNil(nextOffset(after: updates))
    }

    func testDecodeUpdatesNotOK() {
        let json = """
        {"ok": false, "description": "Unauthorized"}
        """
        let data = Data(json.utf8)
        XCTAssertThrowsError(try decodeUpdates(data)) { error in
            XCTAssertEqual(error as? TelegramError, .notOK("Unauthorized"))
        }
    }

    func testDecodeUpdatesInvalidJSON() {
        let data = Data("not json".utf8)
        XCTAssertThrowsError(try decodeUpdates(data))
    }

    func testNextOffset() {
        let json = """
        {"ok": true, "description": "...", "result": [
          {"update_id": 1, "message": {"from": {"id": 11}, "chat": {"id": -100}, "text": "/status"}},
          {"update_id": 2, "callback_query": {"id": "cb1", "from": {"id": 11},
                                              "message": {"chat": {"id": -100}}, "data": "approve:r1"}}
        ]}
        """
        let data = Data(json.utf8)
        let updates = try! decodeUpdates(data)
        XCTAssertEqual(nextOffset(after: updates), 3)
    }

    func testCallbackCarriesMessageAndName() {
        let json = """
        {"ok": true, "result": [{"update_id": 3, "callback_query": {"id": "cb2",
          "from": {"id": 11, "first_name": "Ann"},
          "message": {"message_id": 42, "chat": {"id": -100}}, "data": "deny:r2"}}]}
        """
        let updates = try! decodeUpdates(Data(json.utf8))
        XCTAssertEqual(updates, [TelegramUpdate(updateID: 3, event: .callback(
            id: "cb2", chatID: -100, fromID: 11, data: "deny:r2", messageID: 42, fromName: "Ann"))])
    }

    func testIsFromParent() {
        let config = Config(childUser: "a", telegramChatID: "-100", parentUserIDs: [11])
        XCTAssertTrue(isFromParent(chatID: -100, fromID: 11, config: config))
        XCTAssertFalse(isFromParent(chatID: -100, fromID: 12, config: config))
        XCTAssertFalse(isFromParent(chatID: -200, fromID: 11, config: config))

        let config2 = Config(childUser: "a", telegramChatID: "-100")
        XCTAssertTrue(isFromParent(chatID: -100, fromID: 12, config: config2))

        let config3 = Config(childUser: "a")
        XCTAssertFalse(isFromParent(chatID: -100, fromID: 11, config: config3))
    }
}
