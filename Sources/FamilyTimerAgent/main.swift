import AppKit

// FamilyTimerAgent: the child's face (SPEC 3). Started by a LaunchAgent in every GUI session.
//   FAMILYTIMER_SOCKET   daemon socket (default /var/run/familytimer.sock)

let socketPath = ProcessInfo.processInfo.environment["FAMILYTIMER_SOCKET"] ?? "/var/run/familytimer.sock"
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
MainActor.assumeIsolated {
    let controller = AgentController(socketPath: socketPath)
    controller.start()
    withExtendedLifetime(controller) { app.run() }
}
