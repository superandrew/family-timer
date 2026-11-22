import Foundation
import FamilyTimerCore

/// Where the agent's messages go. Task 007 replaces the logging stub with the socket.
protocol AgentLink: Sendable {
    func send(_ action: PolicyAction) async
}

struct LoggingAgentLink: AgentLink {
    func send(_ action: PolicyAction) async {
        Log.info("agent <- \(action) (no agent yet)")
    }
}

struct Paths {
    var config: URL
    var stateDir: URL
    var state: URL { stateDir.appendingPathComponent("state.json") }
    var telegram: URL { stateDir.appendingPathComponent("telegram.json") }
}

actor Daemon {
    static let tickSeconds = 15

    let config: Config
    let paths: Paths
    let dryRun: Bool
    let calendar = Calendar.current
    let telegram: TelegramClient?
    let agent: AgentLink

    private var state: PolicyState
    private var offset: Int64?
    /// Request id -> (message id, text) of the Telegram message with the buttons.
    private var requestMessages: [String: (id: Int64, text: String)] = [:]
    private var lastSummary = Date.distantPast

    init(config: Config, paths: Paths, dryRun: Bool, agent: AgentLink) {
        self.config = config
        self.paths = paths
        self.dryRun = dryRun
        self.agent = agent
        if !config.telegramBotToken.isEmpty, let chat = Int64(config.telegramChatID) {
            telegram = TelegramClient(token: config.telegramBotToken, chatID: chat)
        } else {
            telegram = nil
        }
        let now = Date()
        if let data = try? Data(contentsOf: paths.state),
           let saved = try? JSONDecoder().decode(PolicyState.self, from: data) {
            state = saved
        } else {
            state = PolicyState.fresh(for: now, calendar: Calendar.current)
        }
        if let data = try? Data(contentsOf: paths.telegram),
           let saved = try? JSONDecoder().decode([String: Int64].self, from: data) {
            offset = saved["offset"]
        }
    }

    func describe() -> String {
        let remaining = Policy.remaining(state, now: Date(), config: config, calendar: calendar)
        return "day \(state.ledger.day) used \(state.ledger.used)s extra \(state.ledger.extra)s "
            + "remaining \(remaining)s phase \(state.phase.rawValue)"
            + (state.ledger.lockedByParent ? " (parent lock)" : "")
    }

    // MARK: events

    func tick() async {
        let console = System.consoleUser()
        let idle = System.hidIdleSeconds() ?? .infinity
        let active = console?.name == config.childUser && idle < Double(config.idleThreshold)
        await apply(.tick(seconds: Self.tickSeconds, active: active), console: console)
        if Date().timeIntervalSince(lastSummary) >= 300 {
            lastSummary = Date()
            Log.info("status: \(describe()) console \(console?.name ?? "-") idle \(Int(idle))s")
        }
    }

    /// Reduce, persist, then perform the actions.
    @discardableResult
    func apply(_ event: PolicyEvent, console: (name: String, uid: uid_t)? = nil) async -> [PolicyAction] {
        let before = state
        let (after, actions) = Policy.reduce(state, event, now: Date(), config: config, calendar: calendar)
        state = after
        if after != before { save() }
        if after.phase != before.phase || after.ledger.day != before.ledger.day {
            Log.info("\(event) -> \(describe())")
        }
        for action in actions {
            await perform(action, console: console)
        }
        return actions
    }

    private func perform(_ action: PolicyAction, console: (name: String, uid: uid_t)?) async {
        switch action {
        case .showExpiredDialog, .lock, .unlock, .requestResult:
            await agent.send(action)
        case let .sendTimeRequest(requestID, seconds):
            let text = Replies.request(child: config.childUser, seconds: seconds, config.language)
            do {
                let id = try await telegram?.send(text, buttons: [
                    (Replies.approveButton(config.language), "approve:\(requestID)"),
                    (Replies.denyButton(config.language), "deny:\(requestID)"),
                ]) ?? 0
                requestMessages[requestID] = (id, text)
                Log.info("request \(requestID) sent to Telegram")
            } catch {
                Log.info("request \(requestID) NOT sent: \(error.localizedDescription)")
            }
        case let .cancelRequest(requestID):
            if let message = requestMessages.removeValue(forKey: requestID) {
                try? await telegram?.edit(messageID: message.id, text: Replies.superseded(message.text, config.language))
            }
        case .logout:
            guard let console, console.name == config.childUser else { return }
            if dryRun {
                Log.info("DRY_RUN: would log out \(console.name) (uid \(console.uid))")
            } else {
                let status = System.logout(uid: console.uid)
                Log.info("logged out \(console.name) (uid \(console.uid)): exit \(status)")
            }
        }
    }

    // MARK: Telegram

    func pollTelegram() async {
        guard let telegram else { return }
        do {
            let updates = try await telegram.getUpdates(offset: offset)
            for update in updates {
                await handle(update.event, telegram: telegram)
            }
            if let next = nextOffset(after: updates) {
                offset = next
                saveOffset()
            }
        } catch {
            Log.info("getUpdates failed: \(error.localizedDescription)")
            try? await Task.sleep(nanoseconds: 5_000_000_000)
        }
    }

    private func handle(_ event: TelegramEvent, telegram: TelegramClient) async {
        switch event {
        case let .message(chatID, fromID, text):
            guard text.hasPrefix("/") else { return }
            guard isFromParent(chatID: chatID, fromID: fromID, config: config) else {
                Log.info("ignored \(text.prefix(20)) from \(fromID) in chat \(chatID)")
                return
            }
            let reply: String
            switch parseCommand(text) {
            case let .success(command):
                await apply(.command(command), console: System.consoleUser())
                reply = Replies.reply(to: command, after: state, now: Date(), config: config, calendar: calendar)
                Log.info("command \(command) from \(fromID)")
            case let .failure(error):
                reply = Replies.error(error, config.language)
                Log.info("bad command \(error) from \(fromID)")
            }
            do { try await telegram.send(reply) } catch {
                Log.info("reply NOT sent: \(error.localizedDescription)")
            }

        case let .callback(id, chatID, fromID, data, messageID, fromName):
            guard isFromParent(chatID: chatID, fromID: fromID, config: config) else {
                try? await telegram.answerCallback(id: id, text: Replies.parentsOnly(config.language))
                return
            }
            let parts = data.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2, parts[0] == "approve" || parts[0] == "deny" else {
                try? await telegram.answerCallback(id: id, text: "?")
                return
            }
            let approved = parts[0] == "approve"
            let actions = await apply(.answer(requestID: parts[1], approved: approved),
                                      console: System.consoleUser())
            let applied = actions.contains(.requestResult(requestID: parts[1], approved: approved))
            try? await telegram.answerCallback(
                id: id, text: Replies.callbackAnswer(applied: applied, approved: approved, config.language))
            if applied {
                let text = requestMessages.removeValue(forKey: parts[1])?.text
                    ?? Replies.request(child: config.childUser, seconds: config.extensionTime, config.language)
                try? await telegram.edit(messageID: messageID,
                                         text: Replies.decided(text, approved: approved, by: fromName, config.language))
                Log.info("request \(parts[1]) \(approved ? "approved" : "denied") by \(fromID)")
            }

        case .other:
            break
        }
    }

    // MARK: persistence

    private func save() {
        do {
            try write(JSONEncoder().encode(state), to: paths.state)
        } catch {
            Log.info("cannot save state: \(error.localizedDescription)")
        }
    }

    private func saveOffset() {
        guard let offset else { return }
        try? write(JSONEncoder().encode(["offset": offset]), to: paths.telegram)
    }

    private func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        chmod(url.path, 0o600)
    }
}
