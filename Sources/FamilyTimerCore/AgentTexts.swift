import Foundation

/// Texts the child sees (menu bar and dialogs), in the language the daemon sends.
public enum AgentTexts {
    private static func t(_ language: Language, _ en: String, _ it: String) -> String {
        switch language {
        case .en: return en
        case .it: return it
        }
    }

    /// Menu bar title.
    public static func menuTitle(remaining: Int, phase: Phase, graceRemaining: Int?, _ l: Language,
                                 minecraftRemaining: Int? = nil) -> String {
        switch phase {
        case .open:
            var title = "⏱ " + Replies.duration(remaining + 59)
            if let mc = minecraftRemaining {
                title += " ⛏ " + Replies.duration(mc + 59)
            }
            return title
        case .grace, .pending:
            return "⏱ " + t(l, "time over", "tempo finito")
                + (graceRemaining.map { " (\(Replies.duration($0 + 59)))" } ?? "")
        case .locked:
            return "⏱ " + t(l, "locked", "bloccato")
        }
    }

    /// Lines of the menu bar menu: time left, Minecraft left, study time, today's top apps.
    public static func menuLines(_ state: PolicyState, now: Date, config: Config, calendar: Calendar,
                                 minecraftPlayed: Int?, today: [UsageEntry],
                                 categories: [String: UsageCategory]) -> [String] {
        let l = config.language
        let ledger = state.ledger
        let budget = DayLedger.budget(for: now, config: config, calendar: calendar)
        var lines: [String] = []

        let remaining = ledger.remaining(budget: budget)
        let left = remaining == 0 ? "0m" : Replies.duration(remaining + 59)
        let total = Replies.duration(budget + ledger.extra)
        let used = Replies.duration(ledger.used)
        lines.append(t(l, "Computer: \(left) left (used \(used) of \(total))",
                       "Computer: restano \(left) (usati \(used) su \(total))"))

        if let played = minecraftPlayed,
           let mcLeft = Policy.minecraftRemaining(state, played: played, now: now, config: config, calendar: calendar) {
            let mcTotal = DayLedger.minecraftBudget(for: now, config: config, calendar: calendar) + (ledger.minecraftExtra ?? 0)
            let mcLeftStr = mcLeft == 0 ? "0m" : Replies.duration(mcLeft + 59)
            lines.append(t(l, "Minecraft: \(mcLeftStr) left (played \(Replies.duration(played)) of \(Replies.duration(mcTotal)))",
                           "Minecraft: restano \(mcLeftStr) (giocati \(Replies.duration(played)) su \(Replies.duration(mcTotal)))"))
        }

        if ledger.inStudio(at: now), let until = ledger.studioUntil {
            let c = Replies.clock(until, calendar: calendar)
            lines.append(t(l, "Study time until \(c)", "Studio fino alle \(c)"))
        }

        let apps = today.filter { !UsageLog.isSite($0.key) && $0.seconds >= 60 }.prefix(3)
        if !apps.isEmpty {
            lines.append(t(l, "Today:", "Oggi:"))
            for e in apps {
                let emoji = UsageLog.isBrowser(e.key) ? "🌐" : Replies.categoryEmoji(categories[e.key])
                lines.append("\(emoji) \(e.name) \(Replies.duration(e.seconds))")
            }
        }

        return lines
    }

    /// Warning shown when `minutes` are left (5 and 1).
    public static func warning(minutes: Int, _ l: Language) -> String {
        minutes == 1
            ? t(l, "1 minute left today. Save your work.", "Manca 1 minuto. Salva quello che stai facendo.")
            : t(l, "\(minutes) minutes left today.", "Mancano \(minutes) minuti per oggi.")
    }

    public static func expired(graceRemaining: Int?, _ l: Language) -> String {
        let minutes = Replies.duration((graceRemaining ?? 0) + 59)
        return t(l, "Today's time is over. The screen locks in \(minutes).\nYou can ask a parent for more time.",
                    "Il tempo di oggi è finito. Lo schermo si blocca tra \(minutes).\nPuoi chiedere altro tempo ai genitori.")
    }

    public static func askButton(_ l: Language) -> String { t(l, "Ask for more time", "Chiedi altro tempo") }
    public static func okButton(_ l: Language) -> String { "OK" }

    public static func reasonPrompt(_ l: Language) -> String {
        t(l, "Ask for more time.\nWhat do you need it for? (optional)",
             "Chiedi altro tempo.\nCosa devi fare? (facoltativo)")
    }
    public static func reasonPlaceholder(_ l: Language) -> String {
        t(l, "e.g. finish my maths homework", "es. finire i compiti di matematica")
    }
    public static func sendButton(_ l: Language) -> String { t(l, "Send", "Invia") }
    public static func cancelButton(_ l: Language) -> String { t(l, "Cancel", "Annulla") }

    public static func waiting(_ l: Language) -> String {
        t(l, "Request sent. Waiting for a parent…", "Richiesta inviata. Aspetta la risposta di un genitore…")
    }

    public static func result(approved: Bool, _ l: Language) -> String {
        approved
            ? t(l, "A parent said yes: more time added.", "Un genitore ha detto sì: tempo aggiunto.")
            : t(l, "A parent said no.", "Un genitore ha detto no.")
    }

    public static func lockedAsk(_ l: Language) -> String {
        t(l, "Today's time is over. You can ask a parent for more time.",
          "Il tempo di oggi è finito. Puoi chiedere altro tempo ai genitori.")
    }

    public static func lockedWaiting(_ l: Language) -> String {
        t(l, "Request sent. Waiting for a parent's answer.",
          "Richiesta inviata. Aspetta la risposta dei genitori.")
    }

    public static func lockedDenied(_ l: Language) -> String {
        t(l, "A parent said no: today's time is over.",
          "Un genitore ha detto no: per oggi il tempo è finito.")
    }

    public static func lockedOver(_ l: Language) -> String {
        t(l, "Today's time is over.",
          "Il tempo di oggi è finito.")
    }

    public static func minecraftWarning(minutes: Int, _ l: Language) -> String {
        minutes == 1
            ? t(l, "Minecraft: 1 minute left today. Save your world.",
                "Minecraft: manca 1 minuto. Salva il mondo.")
            : t(l, "Minecraft: \(minutes) minutes left today.",
                "Minecraft: mancano \(minutes) minuti per oggi.")
    }

    public static func closed(app: String, reason: BlockReason, _ l: Language) -> String {
        switch reason {
        case .minecraftOver:
            return t(l, "Minecraft time is over for today. The game is closing.",
                     "Il tempo di Minecraft per oggi è finito. Il gioco si chiude.")
        case .studio:
            return t(l, "Study time: “\(app)” is closing.",
                     "È tempo di studio: «\(app)» si chiude.")
        }
    }
}
