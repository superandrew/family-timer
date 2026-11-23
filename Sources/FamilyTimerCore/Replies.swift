import Foundation

/// Texts the daemon sends to Telegram, in the config's language. Pure, so they are tested
/// like the rest of the core. To add a language: a case in `Language` and one more
/// argument to `t` everywhere below.
public enum Replies {
    private static func t(_ language: Language, _ en: String, _ it: String) -> String {
        switch language {
        case .en: return en
        case .it: return it
        }
    }

    /// `3900` -> `"1h 05m"`, `2700` -> `"45m"`. Seconds are dropped. Same in every language.
    public static func duration(_ seconds: Int) -> String {
        let minutes = max(0, seconds) / 60
        if minutes >= 60 {
            return String(format: "%dh %02dm", minutes / 60, minutes % 60)
        }
        return "\(minutes)m"
    }

    /// `"14:05"` in the calendar's time zone.
    public static func clock(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    public static func phaseName(_ phase: Phase, _ language: Language) -> String {
        switch phase {
        case .open: return t(language, "open", "aperto")
        case .grace: return t(language, "time over, grace period", "tempo finito, periodo di grazia")
        case .pending: return t(language, "waiting for a parent", "in attesa di un genitore")
        case .locked: return t(language, "locked", "bloccato")
        }
    }

    /// `agentConnected`: whether the menu bar app is connected (nil: unknown, not shown).
    public static func status(_ state: PolicyState, now: Date, config: Config,
                              calendar: Calendar, agentConnected: Bool? = nil) -> String {
        let l = config.language
        let budget = DayLedger.budget(for: now, config: config, calendar: calendar)
        let ledger = state.ledger
        let extra = ledger.extra > 0 ? " + \(duration(ledger.extra)) extra" : ""
        let remaining = duration(ledger.remaining(budget: budget))
        var lines = [
            t(l, "\(config.displayName): used \(duration(ledger.used)) of \(duration(budget))\(extra).",
                 "\(config.displayName): usati \(duration(ledger.used)) su \(duration(budget))\(extra)."),
            t(l, "Remaining: \(remaining). State: \(phaseName(state.phase, l)).",
                 "Rimasti: \(remaining). Stato: \(phaseName(state.phase, l))."),
        ]
        if let until = ledger.studioUntil, ledger.inStudio(at: now) {
            let c = clock(until, calendar: calendar)
            lines.append(t(l, "Study time until \(c).", "Studio fino alle \(c)."))
        }
        if ledger.lockedByParent {
            lines.append(t(l, "Locked by a parent until midnight or /unlock.",
                              "Bloccato da un genitore fino a mezzanotte o /unlock."))
        }
        if let agentConnected {
            lines.append(agentConnected ? t(l, "Menu bar app: connected.", "App nella barra: collegata.")
                                        : t(l, "Menu bar app: not connected.", "App nella barra: non collegata."))
        }
        return lines.joined(separator: "\n")
    }

    /// The answer to a parent command, given the state after the command. Starts with the
    /// child's name: with one bot per child in the same group, every answer says whose it is.
    public static func reply(to command: Command, after state: PolicyState, now: Date,
                             config: Config, calendar: Calendar, agentConnected: Bool? = nil) -> String {
        switch command {
        case .status:
            return status(state, now: now, config: config, calendar: calendar, agentConnected: agentConnected)
        case .help:
            return body(to: command, after: state, now: now, config: config, calendar: calendar)
        default:
            return config.displayName + ": "
                + body(to: command, after: state, now: now, config: config, calendar: calendar)
        }
    }

    private static func body(to command: Command, after state: PolicyState, now: Date,
                             config: Config, calendar: Calendar) -> String {
        let l = config.language
        let remaining = duration(Policy.remaining(state, now: now, config: config, calendar: calendar))
        let stillLocked = state.ledger.lockedByParent
            ? t(l, " Still locked by /lock.", " Resta bloccato da /lock.") : ""
        switch command {
        case .status:
            return status(state, now: now, config: config, calendar: calendar)
        case .help:
            return help(l)
        case let .extra(seconds):
            return t(l, "Added \(duration(seconds)). Remaining: \(remaining).",
                        "Aggiunti \(duration(seconds)). Rimasti: \(remaining).") + stillLocked
        case .studio:
            let until = state.ledger.studioUntil.map { clock($0, calendar: calendar) } ?? "?"
            return t(l, "Study time until \(until): time does not count.",
                        "Studio fino alle \(until): il tempo non conta.") + stillLocked
        case .lock:
            return t(l, "Locked until midnight or /unlock.", "Bloccato fino a mezzanotte o /unlock.")
        case .unlock:
            return state.phase == .locked
                ? t(l, "Parent lock removed, but no time is left: still locked. Use /extra or /studio.",
                       "Blocco del genitore tolto, ma il tempo è finito: resta bloccato. Usa /extra o /studio.")
                : t(l, "Unlocked. Remaining: \(remaining).", "Sbloccato. Rimasti: \(remaining).")
        case .apps:
            return ""
        case .minecraft:
            return ""
        }
    }

    public static func error(_ error: CommandError, _ l: Language) -> String {
        switch error {
        case let .unknown(word):
            return t(l, "Unknown command \(word). /help lists the commands.",
                        "Comando sconosciuto \(word). /help elenca i comandi.")
        case let .missingDuration(word):
            return t(l, "\(word) needs a duration, for example \(word) 30 or \(word) 1h30.",
                        "\(word) vuole una durata, per esempio \(word) 30 o \(word) 1h30.")
        case let .invalidDuration(text):
            return t(l, "\"\(text)\" is not a duration between 1 minute and 12 hours (30, 45m, 2h, 1h30).",
                        "\"\(text)\" non è una durata tra 1 minuto e 12 ore (30, 45m, 2h, 1h30).")
        }
    }

    public static func help(_ l: Language) -> String {
        t(l, """
            /status - time used and left today
            /extra 30 - add time today (30, 45m, 2h, 1h30)
            /studio 2h - study time: the next 2 hours do not count
            /lock - lock until midnight or /unlock
            /unlock - remove /lock
            /app - apps and sites of the last 7 days
            /oggi - apps and sites of today
            Add a name to act on one child only: /extra 30 ann, /lock ann.
            """, """
            /status - tempo usato e rimasto oggi
            /extra 30 - aggiunge tempo oggi (30, 45m, 2h, 1h30)
            /studio 2h - studio: le prossime 2 ore non contano
            /lock - blocca fino a mezzanotte o /unlock
            /unlock - toglie /lock
            /app - app e siti degli ultimi 7 giorni
            /oggi - app e siti di oggi
            Aggiungi un nome per un solo figlio: /extra 30 ann, /lock ann.
            """)
    }

    public static func request(child: String, seconds: Int, remaining: Int? = nil, _ l: Language) -> String {
        if let remaining, remaining > 0 {
            return t(l, "⏰ \(child) has \(duration(remaining)) left and asks for \(duration(seconds)) more.",
                     "⏰ \(child) ha ancora \(duration(remaining)) e chiede altri \(duration(seconds)).")
        }
        return t(l, "⏰ \(child) has used today's time and asks for \(duration(seconds)) more.",
                 "⏰ \(child) ha finito il tempo di oggi e chiede altri \(duration(seconds)).")
    }

    public static func approveButton(_ l: Language) -> String { t(l, "✅ Approve", "✅ Approva") }
    public static func denyButton(_ l: Language) -> String { t(l, "❌ Deny", "❌ Nega") }

    public static func decided(_ request: String, approved: Bool, by name: String, _ l: Language) -> String {
        let outcome = approved ? t(l, "✅ Approved", "✅ Approvato") : t(l, "❌ Denied", "❌ Negato")
        let who = name.isEmpty ? "" : t(l, " by \(name)", " da \(name)")
        return request + "\n" + outcome + who + "."
    }

    public static func superseded(_ request: String, _ l: Language) -> String {
        request + "\n" + t(l, "(No longer needed.)", "(Non serve più.)")
    }

    /// The short toast after a button press.
    public static func callbackAnswer(applied: Bool, approved: Bool, _ l: Language) -> String {
        guard applied else { return t(l, "Already decided or expired.", "Già deciso o scaduto.") }
        return approved ? t(l, "Approved", "Approvato") : t(l, "Denied", "Negato")
    }

    public static func parentsOnly(_ l: Language) -> String {
        t(l, "Only parents can answer.", "Solo i genitori possono rispondere.")
    }

    /// AgentWatch gave up restarting the menu bar app: the child has no countdown or dialog.
    public static func agentMissing(child: String, _ l: Language) -> String {
        t(l, "⚠️ \(child): the menu bar app on the Mac does not respond (restarted twice). "
             + "Time still counts and the lock still works, but without warnings.",
             "⚠️ \(child): l'app nella barra del Mac non risponde (riavviata due volte). "
             + "Il tempo conta e il blocco funziona, ma senza avvisi.")
    }

    public static func accessibilityMissing(child: String, _ l: Language) -> String {
        t(l, "ℹ️ \(child): apps are recorded, sites are not: on that Mac, an admin must turn on "
             + "FamilyTimerAgent in System Settings › Privacy & Security › Accessibility.",
             "ℹ️ \(child): le app vengono registrate, i siti no: su quel Mac un amministratore deve "
             + "attivare FamilyTimerAgent in Impostazioni › Privacy e sicurezza › Accessibilità.")
    }

    public static func agentBack(child: String, _ l: Language) -> String {
        t(l, "✅ \(child): the menu bar app is connected again.",
             "✅ \(child): l'app nella barra è di nuovo collegata.")
    }

    /// Emoji of a category; nil (not classified yet) is "❓".
    public static func categoryEmoji(_ c: UsageCategory?) -> String {
        switch c {
        case .games: return "🎮"
        case .study: return "📚"
        case .video: return "📺"
        case .coding: return "💻"
        case .other: return "▫️"
        case nil: return "❓"
        }
    }

    /// Button text: emoji, a space, the name.
    public static func categoryLabel(_ c: UsageCategory, _ l: Language) -> String {
        switch c {
        case .games: return t(l, "🎮 games", "🎮 giochi")
        case .study: return t(l, "📚 study", "📚 studio")
        case .video: return t(l, "📺 video", "📺 video")
        case .coding: return t(l, "💻 coding", "💻 coding")
        case .other: return t(l, "▫️ other", "▫️ altro")
        }
    }

    public static func usage(_ entries: [UsageEntry], categories: [String: UsageCategory],
                             child: String, days: Int, limit: Int, _ l: Language) -> String {
        let header = days == 1
            ? t(l, "\(child), today:", "\(child), oggi:")
            : t(l, "\(child), last \(days) days:", "\(child), ultimi \(days) giorni:")
        var lines = [header]
        if entries.isEmpty {
            lines.append(t(l, "No data yet.", "Ancora nessun dato."))
            return lines.joined(separator: "\n")
        }
        let apps = entries.filter { !UsageLog.isSite($0.key) }.prefix(limit)
        let sites = entries.filter { UsageLog.isSite($0.key) }.prefix(limit)
        if !apps.isEmpty {
            lines.append(t(l, "Apps:", "App:"))
            for e in apps {
                let emoji = UsageLog.isBrowser(e.key) ? "🌐" : categoryEmoji(categories[e.key])
                lines.append("\(emoji) \(e.name) \(duration(e.seconds))")
            }
        }
        if !sites.isEmpty {
            lines.append(t(l, "Sites:", "Siti:"))
            for e in sites {
                lines.append("\(categoryEmoji(categories[e.key])) \(e.name) \(duration(e.seconds))")
            }
        }
        return lines.joined(separator: "\n")
    }

    public static func classifyPrompt(name: String, seconds: Int, _ l: Language) -> String {
        t(l, "What is “\(name)” (\(duration(seconds)))?",
             "Che cos'è «\(name)» (\(duration(seconds)))?")
    }

    public static func classified(name: String, category: UsageCategory, by: String,
                                  _ l: Language) -> String {
        t(l, "“\(name)”: \(categoryLabel(category, l)) (\(by))",
             "«\(name)»: \(categoryLabel(category, l)) (\(by))")
    }
}
