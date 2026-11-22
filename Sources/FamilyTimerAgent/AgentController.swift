import AppKit
import FamilyTimerCore

/// The child's side (SPEC 3): menu bar countdown, warnings, the "time is over" dialog with
/// "Ask for more time", and the lock loop. It decides nothing: phases and time come from the
/// daemon, which also checks the lock by itself.
@MainActor
final class AgentController: NSObject {
    private let connection: AgentConnection
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let askItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let notice = Notice()

    private var language: Language = .en
    private var phase: Phase = .open
    private var remaining: Int?
    private var graceRemaining: Int?
    private var dryRun = false
    private var expiredShown = false
    private var asked = false
    private var dryRunLockLogged = false
    private var askState: AskState = .unavailable
    /// While locked: the child unlocked and sees the small window until this time.
    private var holdUntil: Date?
    /// The last time that window was offered: at most once a minute, then lock at once.
    private var lastOffered: Date?

    init(socketPath: String) {
        connection = AgentConnection(path: socketPath)
        super.init()
    }

    func start() {
        // Hidden until the daemon talks to us: in a parent's session it never does.
        statusItem.isVisible = false
        statusItem.button?.title = "⏱"
        let menu = NSMenu()
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())
        askItem.target = self
        askItem.action = #selector(askPressed)
        menu.addItem(askItem)
        menu.autoenablesItems = false
        statusItem.menu = menu
        refreshMenu()

        connection.onConnected = { [weak self] in self?.connection.send(.hello) }
        connection.onMessage = { [weak self] message in self?.handle(message) }
        connection.start()

        Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.connection.send(.heartbeat) }
        }
        Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.lockLoop() }
        }
    }

    // MARK: daemon messages

    private func handle(_ message: DaemonMessage) {
        switch message.type {
        case .state:
            statusItem.isVisible = true
            if let language = message.language { self.language = language }
            dryRun = message.dryRun ?? false
            askState = message.askState ?? .unavailable
            let previous = remaining
            remaining = message.remaining
            graceRemaining = message.graceRemaining
            if let phase = message.phase { setPhase(phase) }
            if phase == .open, let previous, let now = remaining {
                for minutes in [5, 1] where previous > minutes * 60 && now <= minutes * 60 && now > 0 {
                    notice.show(AgentTexts.warning(minutes: minutes, language), primary: AgentTexts.okButton(language))
                }
            }
            if phase == .grace || phase == .pending {
                notice.update(phase == .pending ? AgentTexts.waiting(language)
                                                : AgentTexts.expired(graceRemaining: graceRemaining, language))
            }
            refreshMenu()
        case .showExpiredDialog:
            setPhase(.grace)
            showExpired()
        case .requestResult:
            notice.show(AgentTexts.result(approved: message.approved ?? false, language),
                        primary: AgentTexts.okButton(language))
        case .lock:
            setPhase(.locked)
            lockLoop(immediate: true)
        case .unlock:
            setPhase(.open)
        }
    }

    private func setPhase(_ new: Phase) {
        if new == .open {
            expiredShown = false
            asked = false
            dryRunLockLogged = false
            holdUntil = nil
            lastOffered = nil
        }
        let entered = new != phase
        if entered && new == .locked {
            notice.close()
        }
        phase = new
        if entered && (new == .grace || new == .pending) && !expiredShown {
            showExpired()
        }
        refreshMenu()
    }

    private func showExpired() {
        expiredShown = true
        if asked || phase == .pending {
            notice.show(AgentTexts.waiting(language), primary: AgentTexts.okButton(language))
        } else {
            notice.show(AgentTexts.expired(graceRemaining: graceRemaining, language),
                        primary: AgentTexts.okButton(language),
                        secondary: AgentTexts.askButton(language), { [weak self] in self?.ask() })
        }
    }

    private func ask() {
        guard !asked else { return }
        asked = true
        connection.send(.requestTime)
        notice.show(AgentTexts.waiting(language), primary: AgentTexts.okButton(language))
        refreshMenu()
    }

    @objc private func askPressed() {
        if phase == .locked {
            askWhileLocked()
        } else {
            ask()
        }
    }

    private func refreshMenu() {
        let title = remaining.map {
            AgentTexts.menuTitle(remaining: $0, phase: phase, graceRemaining: graceRemaining, language)
        } ?? "⏱"
        statusItem.button?.title = title
        statusLine.title = title
        askItem.title = AgentTexts.askButton(language)
        askItem.isEnabled = (phase == .grace && !asked) || (phase == .locked && askState == .available)
    }

    // MARK: lock loop

    /// Every 3 s while locked: lock again if the child unlocked (SPEC 3.2). When the child
    /// unlocks, a small window first says why and, if allowed, offers "Ask for more time"
    /// (15 s, or 5 s with nothing to ask); then the screen locks again. The window is offered
    /// at most once a minute, so the daemon's 30 s lock check is never missed for long.
    private func lockLoop(immediate: Bool = false) {
        guard phase == .locked else { return }
        if Screen.isLocked() {
            connection.send(.locked)
            holdUntil = nil
            return
        }
        if dryRun {
            if !dryRunLockLogged {
                dryRunLockLogged = true
                NSLog("FamilyTimerAgent: DRY_RUN, would lock the screen")
            }
            return
        }
        let now = Date()
        if immediate {
            lockNow()
            return
        }
        if let holdUntil {
            if now >= holdUntil { lockNow() }
            return
        }
        if let lastOffered, now.timeIntervalSince(lastOffered) < 60 {
            lockNow()
            return
        }
        lastOffered = now
        let ok = AgentTexts.okButton(language)
        switch askState {
        case .available:
            hold(15)
            notice.show(AgentTexts.lockedAsk(language), primary: ok, { [weak self] in self?.lockNow() },
                        secondary: AgentTexts.askButton(language), { [weak self] in self?.askWhileLocked() })
        case .waiting:
            hold(5)
            notice.show(AgentTexts.lockedWaiting(language), primary: ok, { [weak self] in self?.lockNow() })
        case .denied:
            hold(5)
            notice.show(AgentTexts.lockedDenied(language), primary: ok, { [weak self] in self?.lockNow() })
        case .unavailable:
            hold(5)
            notice.show(AgentTexts.lockedOver(language), primary: ok, { [weak self] in self?.lockNow() })
        }
    }

    private func hold(_ seconds: TimeInterval) {
        holdUntil = Date().addingTimeInterval(seconds)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds + 0.1) { [weak self] in
            self?.lockLoop()
        }
    }

    private func lockNow() {
        holdUntil = nil
        notice.close()
        guard phase == .locked, !dryRun, !Screen.isLocked() else { return }
        Screen.lock()
    }

    private func askWhileLocked() {
        guard phase == .locked, askState == .available else { return }
        askState = .waiting
        connection.send(.requestTime)
        notice.show(AgentTexts.lockedWaiting(language), primary: AgentTexts.okButton(language),
                    { [weak self] in self?.lockNow() })
        hold(3)
        refreshMenu()
    }
}

enum Screen {
    static func isLocked() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return session["CGSSessionScreenIsLocked"] as? Bool == true
    }

    /// `SACLockScreenImmediate` from the private login.framework (verified by task 0S1).
    static func lock() {
        typealias LockFunction = @convention(c) () -> Int32
        guard let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_NOW),
              let symbol = dlsym(handle, "SACLockScreenImmediate") else {
            NSLog("FamilyTimerAgent: SACLockScreenImmediate not available")
            return
        }
        _ = unsafeBitCast(symbol, to: LockFunction.self)()
    }
}
