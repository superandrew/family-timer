import Foundation
import FamilyTimerCore

/// Where the agent's messages go (the socket server, or a fake in tests).
protocol AgentLink: Sendable {
    func send(_ action: PolicyAction) async
    func broadcast(_ message: DaemonMessage)
    var hasClients: Bool { get }
}

struct Paths {
    var config: URL
    var stateDir: URL
    var state: URL { stateDir.appendingPathComponent("state.json") }
    var telegram: URL { stateDir.appendingPathComponent("telegram.json") }
    var usage: URL { stateDir.appendingPathComponent("usage.json") }
    var accessibilityNotice: URL { stateDir.appendingPathComponent("accessibility-notice") }
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
    private var watch = AgentWatch()
    /// Whether the child was at the console at the last tick, to notice a new login.
    private var childWasAtConsole = false
    /// Minecraft blocked and still running since then: the daemon kills it a minute later.
    private var minecraftBlockedSince: Date?
    /// The last `close` sent, to send it again at most every 10 s.
    private var lastClose: (key: String, at: Date)?
    /// Seconds per app and per site (SPEC 9), and what the agent last said is in front.
    private var usage = UsageLog()
    private var front: (report: AgentReport, at: Date)?
    /// The child's text for the request being sent (set only around `apply(.askForTime)`).
    private var requestReason: String?

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
        if let data = try? Data(contentsOf: paths.usage),
           let saved = try? JSONDecoder().decode(UsageLog.self, from: data) {
            usage = saved
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
        let childAtConsole = console?.name == config.childUser
        if childAtConsole && !childWasAtConsole {
            // A login while locked: give the agent time to start before the logout fallback.
            await apply(.childLoggedIn, console: console)
        }
        childWasAtConsole = childAtConsole
        if state.phase == .locked, let console, console.name == config.childUser,
           System.isScreenLocked(uid: console.uid) {
            await apply(.lockConfirmed, console: console)
        }
        await apply(.tick(seconds: Self.tickSeconds, active: active), console: console)
        sendState()
        await watchAgent(console: console)
        enforceBlocks()
        if active && state.phase != .locked {
            await countUsage()
        }
        if Date().timeIntervalSince(lastSummary) >= 300 {
            lastSummary = Date()
            Log.info("status: \(describe()) console \(console?.name ?? "-") idle \(Int(idle))s")
        }
    }

    // MARK: usage (SPEC 9)

    func agentReport(_ report: AgentReport) async {
        front = (report, Date())
        if !report.accessibility {
            await noticeAccessibility()
        }
    }

    /// One tick of active use goes to the app in front and, for a browser, to the site.
    /// When something not yet classified passes 10 minutes, the parents are asked once.
    private func countUsage() async {
        guard let front, Date().timeIntervalSince(front.at) < 30,
              let frontmost = front.report.frontmost,
              frontmost.bundleID != "com.apple.loginwindow" else { return }
        var keys = [UsageLog.appKey(frontmost.bundleID)]
        if let url = frontmost.url, let site = UsageLog.siteKey(url: url) { keys.append(site) }
        let before = keys.map { usage.total(for: $0) }
        usage.add(frontmost, seconds: Self.tickSeconds, day: state.ledger.day)
        try? write(JSONEncoder().encode(usage), to: paths.usage)
        for (key, old) in zip(keys, before) where usage.needsCategory(key) {
            let now = usage.total(for: key)
            if old < 600 && now >= 600 {
                await askCategory(key: key, seconds: now)
            }
        }
    }

    private func askCategory(key: String, seconds: Int) async {
        guard let telegram else { return }
        let l = config.language
        let buttons = UsageCategory.allCases.map { (Replies.categoryLabel($0, l), "cat:\($0.rawValue):\(key)") }
        guard buttons.allSatisfy({ $0.1.utf8.count <= 64 }) else { return }
        let name = usage.names[key] ?? key
        let text = config.displayName + ": " + Replies.classifyPrompt(name: name, seconds: seconds, l)
        do { _ = try await telegram.send(text, buttons: buttons) } catch {
            Log.info("category question NOT sent: \(error.localizedDescription)")
        }
    }

    private func usageReply(days: Int) async {
        guard let telegram else { return }
        let now = Date()
        let first = DayLedger.dayKey(now.addingTimeInterval(-Double(days - 1) * 86_400), calendar: calendar)
        let entries = usage.entries(from: first, to: DayLedger.dayKey(now, calendar: calendar))
        let text = Replies.usage(entries, categories: usage.categories, child: config.displayName,
                                 days: days, limit: 12, config.language)
        do { _ = try await telegram.send(text) } catch {
            Log.info("reply NOT sent: \(error.localizedDescription)")
        }
        for entry in entries.filter({ usage.needsCategory($0.key) && $0.seconds >= 300 }).prefix(5) {
            await askCategory(key: entry.key, seconds: entry.seconds)
        }
    }

    /// Without the Accessibility permission the agent cannot read the browser's address:
    /// tell the parents, at most once a day.
    private func noticeAccessibility() async {
        let fm = FileManager.default
        if let date = (try? fm.attributesOfItem(atPath: paths.accessibilityNotice.path))?[.modificationDate] as? Date,
           Date().timeIntervalSince(date) < 86_400 { return }
        fm.createFile(atPath: paths.accessibilityNotice.path, contents: Data())
        Log.info("agent has no Accessibility permission: sites are not recorded")
        _ = try? await telegram?.send(Replies.accessibilityMissing(child: config.displayName, config.language))
    }

    /// Restarts the menu bar app when the child is at the console without it, then tells the
    /// parents if that did not help (AgentWatch), and again when it is back.
    private func watchAgent(console: (name: String, uid: uid_t)?) async {
        let atConsole = console?.name == config.childUser
        let action = watch.check(now: Date(), childAtConsole: atConsole, agentConnected: agent.hasClients)
        switch action {
        case .restart:
            guard let console else { return }
            let result = System.restartAgent(uid: console.uid, user: console.name)
            Log.info("agent missing for \(console.name): restart \(watch.restarts)/\(AgentWatch.maxRestarts), \(result)")
        case .notifyMissing:
            Log.info("agent still missing after \(AgentWatch.maxRestarts) restarts: telling the parents")
            _ = try? await telegram?.send(Replies.agentMissing(child: config.displayName, config.language))
        case .notifyBack:
            Log.info("agent back: telling the parents")
            _ = try? await telegram?.send(Replies.agentBack(child: config.displayName, config.language))
        case nil:
            break
        }
    }

    /// Minecraft seconds counted today (only while in front and in use).
    private var minecraftPlayed: Int {
        usage.days.first(where: { $0.day == state.ledger.day })?.seconds[Blocking.minecraftKey] ?? 0
    }

    private func minecraftRemaining(_ now: Date) -> Int? {
        Policy.minecraftRemaining(state, played: minecraftPlayed, now: now, config: config, calendar: calendar)
    }

    /// Minecraft over, or a study window (SPEC 4.5): the agent closes the app in front. For
    /// Minecraft the daemon also looks at the process list, in front or not, and kills the
    /// game itself if it is still running a minute after the agent was told.
    private func enforceBlocks() {
        let now = Date()
        let left = minecraftRemaining(now)
        let inStudio = state.ledger.inStudio(at: now)
        if let front, now.timeIntervalSince(front.at) < 30, let frontmost = front.report.frontmost {
            let key = UsageLog.appKey(frontmost.bundleID)
            if let reason = Blocking.reason(appKey: key, category: usage.categories[key],
                                            minecraftRemaining: left, inStudio: inStudio) {
                close(key, reason, now: now)
            }
        }
        guard let reason = Blocking.reason(appKey: Blocking.minecraftKey, category: nil,
                                           minecraftRemaining: left, inStudio: inStudio) else {
            minecraftBlockedSince = nil
            return
        }
        let pids = System.minecraftPIDs(user: config.childUser)
        guard !pids.isEmpty else {
            minecraftBlockedSince = nil
            return
        }
        guard let since = minecraftBlockedSince else {
            minecraftBlockedSince = now
            close(Blocking.minecraftKey, reason, now: now)
            return
        }
        guard now.timeIntervalSince(since) >= 60 else { return }
        if dryRun {
            Log.info("DRY_RUN: would kill Minecraft \(pids)")
        } else {
            for pid in pids { kill(pid, SIGKILL) }
            Log.info("Minecraft still running a minute after close (\(reason.rawValue)): killed \(pids)")
        }
        minecraftBlockedSince = now
    }

    private func close(_ key: String, _ reason: BlockReason, now: Date) {
        if let lastClose, lastClose.key == key, now.timeIntervalSince(lastClose.at) < 10 { return }
        lastClose = (key, now)
        if dryRun {
            Log.info("DRY_RUN: would close \(key) (\(reason.rawValue))")
            return
        }
        Log.info("agent <- close \(key) (\(reason.rawValue))")
        agent.broadcast(DaemonMessage(type: .close, app: key, reason: reason))
    }

    /// The periodic `state` message: the agent's countdown and phase.
    func sendState() {
        let now = Date()
        agent.broadcast(DaemonMessage(
            type: .state,
            remaining: Policy.remaining(state, now: now, config: config, calendar: calendar),
            phase: state.phase,
            graceRemaining: state.graceUntil.map { max(0, Int($0.timeIntervalSince(now))) },
            dryRun: dryRun,
            language: config.language,
            askState: Policy.askState(state, config: config, now: now, calendar: calendar),
            minecraftRemaining: minecraftRemaining(now),
            menu: AgentTexts.menuLines(state, now: now, config: config, calendar: calendar,
                                       minecraftPlayed: minecraftPlayed,
                                       today: usage.entries(from: state.ledger.day, to: state.ledger.day),
                                       categories: usage.categories)))
    }

    func agentMessage(_ message: AgentMessage) async {
        switch message {
        case .hello:
            await apply(.agentConnected, console: System.consoleUser())
            sendState()
        case .heartbeat:
            break
        case .requestTime:
            await askForTime(reason: nil)
        case .locked:
            // Informational only: the daemon reads the lock state itself in `tick`.
            break
        }
    }

    /// "Ask for more time", with what the child wrote (cleaned; shown to the parents only).
    func askForTime(reason: String?) async {
        let id = String(UUID().uuidString.prefix(8)).lowercased()
        requestReason = Replies.cleanReason(reason)
        Log.info("agent asks for more time (request \(id)\(requestReason == nil ? "" : ", with a reason"))")
        await apply(.askForTime(requestID: id), console: System.consoleUser())
        requestReason = nil
        sendState()
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
            Log.info("agent <- \(action)")
            await agent.send(action)
        case let .sendTimeRequest(requestID, seconds):
            // Asked before the end (SPEC 4.2): the parents see how much is left.
            let left = state.phase == .open
                ? Policy.remaining(state, now: Date(), config: config, calendar: calendar) : nil
            let text = Replies.request(child: config.displayName, seconds: seconds, remaining: left,
                                       reason: requestReason, config.language)
            do {
                // The parent chooses the amount: approve:<id>:<seconds> (SPEC 6).
                let id = try await telegram?.send(text, buttons: Replies.approveChoices.map {
                    (Replies.approveChoiceButton(seconds: $0), "approve:\(requestID):\($0)")
                } + [(Replies.denyButton(config.language), "deny:\(requestID)")]) ?? 0
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
            let (parsed, target) = parseAddressedCommand(text)
            // Another child's bot in the same group answers this one.
            guard config.isAddressed(by: target) else { return }
            if case let .success(.apps(days)) = parsed {
                Log.info("command apps(\(days)) from \(fromID)")
                await usageReply(days: days)
                return
            }
            let reply: String
            switch parsed {
            case let .success(command):
                await apply(.command(command), console: System.consoleUser())
                sendState()
                reply = Replies.reply(to: command, after: state, now: Date(), config: config, calendar: calendar,
                                      agentConnected: agent.hasClients, minecraftPlayed: minecraftPlayed)
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
            if data.hasPrefix("cat:") {
                let parts = data.split(separator: ":", maxSplits: 2).map(String.init)
                guard parts.count == 3, let category = UsageCategory(rawValue: parts[1]) else {
                    try? await telegram.answerCallback(id: id, text: "?")
                    return
                }
                let key = parts[2]
                usage.categories[key] = category
                try? write(JSONEncoder().encode(usage), to: paths.usage)
                try? await telegram.answerCallback(id: id, text: "✓")
                let text = config.displayName + ": " + Replies.classified(
                    name: usage.names[key] ?? key, category: category, by: fromName, config.language)
                try? await telegram.edit(messageID: messageID, text: text)
                Log.info("\(key) is \(category.rawValue) (by \(fromID))")
                return
            }
            guard let answer = parseAnswerData(data) else {
                try? await telegram.answerCallback(id: id, text: "?")
                return
            }
            let approved = answer.approved
            let actions = await apply(.answer(requestID: answer.requestID, approved: approved,
                                              seconds: answer.seconds),
                                      console: System.consoleUser())
            sendState()
            let applied = actions.contains(.requestResult(requestID: answer.requestID, approved: approved))
            try? await telegram.answerCallback(
                id: id, text: Replies.callbackAnswer(applied: applied, approved: approved, config.language))
            if applied {
                let text = requestMessages.removeValue(forKey: answer.requestID)?.text
                    ?? Replies.request(child: config.displayName, seconds: config.extensionTime, config.language)
                try? await telegram.edit(messageID: messageID,
                                         text: Replies.decided(text, approved: approved, by: fromName,
                                                               config.language, seconds: answer.seconds))
                let amount = answer.seconds.map { " \($0)s" } ?? ""
                Log.info("request \(answer.requestID) \(approved ? "approved\(amount)" : "denied") by \(fromID)")
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
