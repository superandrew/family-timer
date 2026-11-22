import AppKit
import FamilyTimerCore

// FamilyTimerAgent: the child's face (SPEC 3). Started by a LaunchAgent in every GUI session.
//   FAMILYTIMER_SOCKET   daemon socket (default /var/run/familytimer.sock)

let socketPath = ProcessInfo.processInfo.environment["FAMILYTIMER_SOCKET"] ?? "/var/run/familytimer.sock"

// One agent per user: launchd and the daemon (when the agent is switched off in Login Items)
// can both start one. A second copy waits here, showing nothing, until the first one quits.
// The lock lives in the user's private temporary folder, so another user cannot hold it.
let lockPath = NSTemporaryDirectory() + FamilyTimer.bundleID + ".agent.lock"
let lockFD = open(lockPath, O_RDONLY | O_CREAT, 0o600)
if lockFD >= 0, flock(lockFD, LOCK_EX | LOCK_NB) != 0 {
    NSLog("FamilyTimerAgent: another agent is running, waiting")
    flock(lockFD, LOCK_EX)
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
MainActor.assumeIsolated {
    let controller = AgentController(socketPath: socketPath)
    controller.start()
    withExtendedLifetime(controller) { app.run() }
}
