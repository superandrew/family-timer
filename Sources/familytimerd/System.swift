import Foundation
import FamilyTimerCore
import IOKit
import SystemConfiguration

/// Small wrappers around the system calls the daemon needs (verified by task 0S1).
enum System {
    /// The user at the console (the one in front of the screen), nil at the login window.
    static func consoleUser() -> (name: String, uid: uid_t)? {
        var uid: uid_t = 0
        var gid: gid_t = 0
        guard let name = SCDynamicStoreCopyConsoleUser(nil, &uid, &gid) as String?,
              name != "loginwindow", !name.isEmpty else { return nil }
        return (name, uid)
    }

    /// Seconds since the last keyboard, mouse or trackpad input, for the whole system.
    static func hidIdleSeconds() -> Double? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard let prop = IORegistryEntryCreateCFProperty(service, "HIDIdleTime" as CFString,
                                                         kCFAllocatorDefault, 0)?.takeRetainedValue(),
              let ns = (prop as? NSNumber)?.uint64Value else { return nil }
        return Double(ns) / 1_000_000_000
    }

    /// True when the GUI session of `uid` shows the lock screen. Read from the IORegistry
    /// (`IOConsoleUsers`, key `CGSSessionScreenIsLocked`, present only while locked): the
    /// daemon checks the lock itself instead of trusting the agent (task 0S1, SPEC 3.1).
    static func isScreenLocked(uid: uid_t) -> Bool {
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        guard root != 0 else { return false }
        defer { IOObjectRelease(root) }
        guard let users = IORegistryEntryCreateCFProperty(root, "IOConsoleUsers" as CFString,
                                                          kCFAllocatorDefault, 0)?.takeRetainedValue()
                as? [[String: Any]] else { return false }
        return users.contains {
            ($0["kCGSSessionUserIDKey"] as? NSNumber)?.uint32Value == uid
                && ($0["CGSSessionScreenIsLocked"] as? Bool) == true
        }
    }

    /// Ends the GUI session of `uid` (the child is logged out). Returns the exit status.
    @discardableResult
    /// Starts the menu bar app in the session of `uid` (AgentWatch). If launchd still has the
    /// job, restart it; if it was booted out, load it again from its plist. If launchd will
    /// not run it (the user switched it off in Login Items, which needs no password), start
    /// the binary directly in that session as that user: the switch only stops launchd.
    static func restartAgent(uid: uid_t, user: String) -> String {
        let label = "\(FamilyTimer.bundleID).agent"
        let service = "gui/\(uid)/\(label)"
        let plist = "/Library/LaunchAgents/\(label).plist"
        var how: String
        if run("/bin/launchctl", ["print", service], quiet: true) == 0 {
            how = "kickstart exit \(run("/bin/launchctl", ["kickstart", "-k", service], quiet: true))"
        } else {
            how = "bootstrap exit \(run("/bin/launchctl", ["bootstrap", "gui/\(uid)", plist], quiet: true))"
        }
        // Switched off in Login Items, launchd loads the job and kills it a second later.
        Thread.sleep(forTimeInterval: 3)
        if output("/bin/launchctl", ["print", service]).contains("state = running") {
            return how
        }
        run("/bin/launchctl", ["bootout", service], quiet: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["asuser", "\(uid)", "/usr/bin/sudo", "-u", user,
                             "/usr/local/libexec/familytimer/FamilyTimerAgent"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()   // not waited for: it runs until the session ends
            return how + ", not running (switched off in Login Items?): started directly"
        } catch {
            return "cannot start: \(error.localizedDescription)"
        }
    }

    static func logout(uid: uid_t) -> Int32 {
        run("/bin/launchctl", ["bootout", "gui/\(uid)"])
    }

    /// Standard output of a command ("" if it cannot run).
    static func output(_ path: String, _ arguments: [String]) -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    @discardableResult
    static func run(_ path: String, _ arguments: [String], quiet: Bool = false) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        if quiet {
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
        }
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            Log.info("cannot run \(path): \(error.localizedDescription)")
            return -1
        }
    }
}

enum Log {
    /// Strings never written to the log (the bot token).
    nonisolated(unsafe) static var secrets: [String] = []

    static func info(_ message: String) {
        var line = "\(ISO8601DateFormatter().string(from: Date())) \(message)"
        for secret in secrets where !secret.isEmpty {
            line = line.replacingOccurrences(of: secret, with: "<redacted>")
        }
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }
}
