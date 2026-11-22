import Foundation
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
    static func logout(uid: uid_t) -> Int32 {
        run("/bin/launchctl", ["bootout", "gui/\(uid)"])
    }

    @discardableResult
    static func run(_ path: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
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
