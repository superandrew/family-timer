import Foundation
import FamilyTimerCore

/// The agent's side of the Unix socket (SPEC 3.3). Connects, reconnects every 3 s when the
/// daemon is not there, and delivers each daemon message on the main queue.
final class AgentConnection: @unchecked Sendable {
    let path: String
    var onMessage: ((DaemonMessage) -> Void)?
    var onConnected: (() -> Void)?

    private let lock = NSLock()
    private var fd: Int32 = -1

    init(path: String) {
        self.path = path
    }

    func start() {
        Thread.detachNewThread { [self] in loop() }
    }

    func send<T: Encodable>(_ message: T) {
        let data = Wire.encode(message)
        lock.lock(); let current = fd; lock.unlock()
        guard current >= 0 else { return }
        _ = data.withUnsafeBytes { write(current, $0.baseAddress, data.count) }
    }

    private func loop() {
        while true {
            var delay: TimeInterval = 3
            if let client = connectOnce() {
                lock.lock(); fd = client; lock.unlock()
                DispatchQueue.main.async { self.onConnected?() }
                // Closed before any message: the daemon refused this user (a parent's
                // session). Retry rarely instead of every 3 s.
                if !read(from: client) { delay = 60 }
                lock.lock(); fd = -1; lock.unlock()
                close(client)
            }
            Thread.sleep(forTimeInterval: delay)
        }
    }

    private func connectOnce() -> Int32? {
        let client = socket(AF_UNIX, SOCK_STREAM, 0)
        guard client >= 0 else { return nil }
        var on: Int32 = 1
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { close(client); return nil }
        withUnsafeMutableBytes(of: &addr.sun_path) { buffer in
            for (i, b) in bytes.enumerated() { buffer[i] = b }
        }
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(client, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if ok != 0 { close(client); return nil }
        return client
    }

    /// Returns true when at least one message arrived before the connection closed.
    private func read(from client: Int32) -> Bool {
        var lines = LineBuffer()
        var chunk = [UInt8](repeating: 0, count: 1024)
        var received = false
        while true {
            let n = Darwin.read(client, &chunk, chunk.count)
            if n <= 0 { return received }
            received = true
            for line in lines.append(Data(chunk[0..<n])) {
                guard let message = try? JSONDecoder().decode(DaemonMessage.self, from: line) else { continue }
                DispatchQueue.main.async { self.onMessage?(message) }
            }
        }
    }
}
