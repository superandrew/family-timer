import Foundation

public enum TelegramError: Error, Equatable {
    case notOK(String)
}

public enum TelegramEvent: Equatable {
    case message(chatID: Int64, fromID: Int64, text: String)
    /// `messageID` is the message with the buttons (to edit it), `fromName` who pressed.
    case callback(id: String, chatID: Int64, fromID: Int64, data: String,
                  messageID: Int64 = 0, fromName: String = "")
    case other
}

public struct TelegramUpdate: Equatable {
    public var updateID: Int64
    public var event: TelegramEvent
}

private struct RawResponse: Decodable {
    var ok: Bool?
    var description: String?
    var result: [RawUpdate]?
}

private struct RawUpdate: Decodable {
    var update_id: Int64
    var message: RawMessage?
    var callback_query: RawCallbackQuery?
}

private struct RawMessage: Decodable {
    var message_id: Int64?
    var from: RawUser?
    var chat: RawChat?
    var text: String?
}

private struct RawCallbackQuery: Decodable {
    var id: String?
    var from: RawUser?
    var message: RawMessage?
    var data: String?
}

private struct RawUser: Decodable {
    var id: Int64?
    var first_name: String?
}

private struct RawChat: Decodable {
    var id: Int64?
}

public func decodeUpdates(_ data: Data) throws -> [TelegramUpdate] {
    let decoder = JSONDecoder()
    let response = try decoder.decode(RawResponse.self, from: data)
    if response.ok != true {
        throw TelegramError.notOK(response.description ?? "")
    }
    let updates = response.result ?? []
    return updates.map { raw in
        var event: TelegramEvent = .other
        if let msg = raw.message,
           let fromID = msg.from?.id,
           let chatID = msg.chat?.id,
           let text = msg.text {
            event = .message(chatID: chatID, fromID: fromID, text: text)
        } else if let cb = raw.callback_query,
                  let id = cb.id,
                  let fromID = cb.from?.id,
                  let chatID = cb.message?.chat?.id,
                  let data = cb.data {
            event = .callback(id: id, chatID: chatID, fromID: fromID, data: data,
                              messageID: cb.message?.message_id ?? 0,
                              fromName: cb.from?.first_name ?? "")
        }
        return TelegramUpdate(updateID: raw.update_id, event: event)
    }
}

public func nextOffset(after updates: [TelegramUpdate]) -> Int64? {
    guard !updates.isEmpty else { return nil }
    return updates.map(\.updateID).max().map { $0 + 1 }
}

public func isFromParent(chatID: Int64, fromID: Int64, config: Config) -> Bool {
    guard let cfgChatID = Int64(config.telegramChatID), cfgChatID == chatID else {
        return false
    }
    if config.parentUserIDs.isEmpty {
        return true
    }
    return config.parentUserIDs.contains(fromID)
}
