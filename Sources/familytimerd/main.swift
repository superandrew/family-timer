import Foundation
import FamilyTimerCore

// familytimerd: the authority (SPEC 3). Runs as root from a LaunchDaemon.
//
// Environment (all optional, for tests and dry runs):
//   FAMILYTIMER_CONFIG     config file (default /Library/Application Support/FamilyTimer/config)
//   FAMILYTIMER_STATE_DIR  folder for state.json (default: the config's folder)
//   FAMILYTIMER_SOCKET     agent socket (default /var/run/familytimer.sock)
//   DRY_RUN=1              log instead of logging the child out; the agent does not lock

let env = ProcessInfo.processInfo.environment
let configURL = URL(fileURLWithPath: env["FAMILYTIMER_CONFIG"]
                    ?? "/Library/Application Support/FamilyTimer/config")
let paths = Paths(config: configURL,
                  stateDir: env["FAMILYTIMER_STATE_DIR"].map { URL(fileURLWithPath: $0) }
                      ?? configURL.deletingLastPathComponent())
let dryRun = env["DRY_RUN"] == "1"

let config: Config
do {
    config = try Config.parse(String(contentsOf: configURL, encoding: .utf8))
} catch {
    Log.info("cannot load \(configURL.path): \(error)")
    exit(78) // EX_CONFIG
}
Log.secrets = [config.telegramBotToken]
try? FileManager.default.createDirectory(at: paths.stateDir, withIntermediateDirectories: true)

signal(SIGPIPE, SIG_IGN)
guard let child = getpwnam(config.childUser) else {
    Log.info("CHILD_USER \(config.childUser) is not a user of this Mac")
    exit(78)
}
let server = AgentServer(path: env["FAMILYTIMER_SOCKET"] ?? "/var/run/familytimer.sock",
                         childUID: child.pointee.pw_uid)
let daemon = Daemon(config: config, paths: paths, dryRun: dryRun, agent: server)
server.onMessage = { message in Task { await daemon.agentMessage(message) } }
do { try server.start() } catch {
    Log.info("cannot open the agent socket: \(error.localizedDescription)")
    exit(71) // EX_OSERR
}
Log.info("familytimerd \(FamilyTimer.version) started\(dryRun ? " in DRY_RUN" : ""), child "
         + "\(config.childUser), telegram \(daemon.telegram == nil ? "off" : "on"), "
         + "healthchecks \(config.healthcheckURL.isEmpty ? "off" : "on"), language \(config.language.rawValue)")
Log.info("state: \(await daemon.describe())")

if let telegram = daemon.telegram {
    do { try await telegram.deleteWebhook() } catch {
        Log.info("deleteWebhook failed: \(error.localizedDescription)")
    }
}

await withTaskGroup(of: Void.self) { group in
    group.addTask {
        while true {
            await daemon.tick()
            try? await Task.sleep(nanoseconds: UInt64(Daemon.tickSeconds) * 1_000_000_000)
        }
    }
    if daemon.telegram != nil {
        group.addTask {
            while true { await daemon.pollTelegram() }
        }
    }
    if let url = URL(string: config.healthcheckURL), !config.healthcheckURL.isEmpty {
        let interval = Double(config.healthcheckInterval)
        group.addTask {
            // Checked every 15 s against the wall clock, so a wake from sleep pings at once.
            var last = Date.distantPast
            while true {
                if Date().timeIntervalSince(last) >= interval {
                    do {
                        var request = URLRequest(url: url)
                        request.timeoutInterval = 10
                        _ = try await URLSession.shared.data(for: request)
                        last = Date()
                    } catch {
                        Log.info("healthcheck ping failed: \(error.localizedDescription)")
                    }
                }
                try? await Task.sleep(nanoseconds: 15_000_000_000)
            }
        }
    }
}
