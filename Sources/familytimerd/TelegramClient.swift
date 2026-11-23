import Foundation
import FamilyTimerCore

/// The few Bot API calls the daemon uses. Errors are logged by the caller with
/// `localizedDescription` only: a full `URLError` would carry the URL with the token.
struct TelegramClient {
    let token: String
    let chatID: Int64

    struct APIError: Error, LocalizedError {
        let description: String
        var errorDescription: String? { description }
    }

    private func call(_ method: String, _ params: [String: Any], timeout: TimeInterval = 15) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://api.telegram.org/bot\(token)/\(method)")!)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: params)
        let (data, _) = try await URLSession.shared.data(for: request)
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           json["ok"] as? Bool != true {
            throw APIError(description: "\(method): \(json["description"] as? String ?? "not ok")")
        }
        return data
    }

    func deleteWebhook() async throws {
        _ = try await call("deleteWebhook", [:])
    }

    /// Long poll: returns after at most `timeout` seconds.
    func getUpdates(offset: Int64?, timeout: Int = 25) async throws -> [TelegramUpdate] {
        var params: [String: Any] = ["timeout": timeout,
                                     "allowed_updates": ["message", "callback_query"]]
        if let offset { params["offset"] = offset }
        let data = try await call("getUpdates", params, timeout: TimeInterval(timeout + 10))
        return try decodeUpdates(data)
    }

    /// Returns the id of the sent message.
    @discardableResult
    func send(_ text: String, buttons: [(text: String, data: String)] = []) async throws -> Int64 {
        var params: [String: Any] = ["chat_id": chatID, "text": text]
        if !buttons.isEmpty {
            // At most 3 per row: 5 category buttons on one row get cut on a phone.
            let cells = buttons.map { ["text": $0.text, "callback_data": $0.data] }
            params["reply_markup"] = ["inline_keyboard": stride(from: 0, to: cells.count, by: 3).map {
                Array(cells[$0..<min($0 + 3, cells.count)])
            }]
        }
        let data = try await call("sendMessage", params)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let result = json?["result"] as? [String: Any]
        return (result?["message_id"] as? NSNumber)?.int64Value ?? 0
    }

    /// Replaces the text and removes the buttons.
    func edit(messageID: Int64, text: String) async throws {
        _ = try await call("editMessageText", ["chat_id": chatID, "message_id": messageID, "text": text])
    }

    func answerCallback(id: String, text: String) async throws {
        _ = try await call("answerCallbackQuery", ["callback_query_id": id, "text": text])
    }
}
