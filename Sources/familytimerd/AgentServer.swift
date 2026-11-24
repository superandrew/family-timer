import Foundation
import FamilyTimerCore

/// The Unix socket the agent connects to (SPEC 3.3). Only connections whose peer uid is
/// the child's are kept: the uid comes from the kernel (`getpeereid`), not from the agent.
final class AgentServer: AgentLink, @unchecked Sendable {
    let path: String
    let childUID: uid_t
    /// Called for every message from an accepted agent.
    var onMessage: (@Sendable (AgentMessage) -> Void)?
    /// Called for every report of what is in front (SPEC 9).
    var onReport: (@Sendable (AgentReport) -> Void)?
    /// Called for "Ask for more time" with the child's text.
    var onTimeRequest: (@Sendable (TimeRequest) -> Void)?

    private let lock = NSLock()
    private var clients: Set<Int32> = []
    private var refusedLogged: Set<uid_t> = []

    init(path: String, childUID: uid_t) {
        self.path = path
        self.childUID = childUID
    }

    var hasClients: Bool {
        lock.lock(); defer { lock.unlock() }
        return !clients.isEmpty
    }

    /// Binds and starts accepting on a background thread.
    func start() throws {
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw posixError("socket") }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { throw posixError("path too long") }
        withUnsafeMutableBytes(of: &addr.sun_path) { buffer in
            for (i, b) in bytes.enumerated() { buffer[i] = b }
        }
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0 else { throw posixError("bind \(path)") }
        chmod(path, 0o666)
        guard listen(fd, 4) == 0 else { throw posixError("listen") }
        Thread.detachNewThread { [self] in acceptLoop(fd) }
    }

    private func acceptLoop(_ listener: Int32) {
        while true {
            let client = accept(listener, nil, nil)
            guard client >= 0 else { continue }
            var uid: uid_t = 0
            var gid: gid_t = 0
            guard getpeereid(client, &uid, &gid) == 0, uid == childUID else {
                if refusedLogged.insert(uid).inserted {
                    Log.info("agent socket: refused uid \(uid) (not the child; logged once)")
                }
                close(client)
                continue
            }
            var on: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            lock.lock(); clients.insert(client); lock.unlock()
            Log.info("agent connected (uid \(uid))")
            Thread.detachNewThread { [self] in readLoop(client) }
        }
    }

    private func readLoop(_ client: Int32) {
        var lines = LineBuffer()
        var chunk = [UInt8](repeating: 0, count: 1024)
        while true {
            let n = read(client, &chunk, chunk.count)
            if n <= 0 { break }
            for line in lines.append(Data(chunk[0..<n])) {
                if let message = try? JSONDecoder().decode(AgentMessage.self, from: line) {
                    onMessage?(message)
                } else if let request = try? JSONDecoder().decode(TimeRequest.self, from: line) {
                    onTimeRequest?(request)
                } else if let report = try? JSONDecoder().decode(AgentReport.self, from: line) {
                    onReport?(report)
                }
            }
        }
        lock.lock(); clients.remove(client); lock.unlock()
        close(client)
        Log.info("agent disconnected")
    }

    func broadcast(_ message: DaemonMessage) {
        let data = Wire.encode(message)
        lock.lock()
        let targets = clients
        lock.unlock()
        for client in targets {
            _ = data.withUnsafeBytes { write(client, $0.baseAddress, data.count) }
        }
    }

    func send(_ action: PolicyAction) async {
        if let message = DaemonMessage.from(action) {
            broadcast(message)
        }
    }

    private func posixError(_ what: String) -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno),
                userInfo: [NSLocalizedDescriptionKey: "\(what): \(String(cString: strerror(errno)))"])
    }
}
