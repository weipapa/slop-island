import Foundation

/// Listens on SlopIsland's own private Unix-domain socket for hook events sent
/// by `slopisland-hook.py`. Decoupled from circleask: it never binds the shared
/// /tmp socket.
///
/// Concurrency model:
/// - accept() runs on a serial queue driven by a DispatchSource.
/// - each client's read/write runs on a concurrent queue so one slow client
///   (a pending permission request) never blocks accept().
/// - pending permission connections are held open (fd kept) until the UI calls
///   `respond`, a timeout fires, or the client disconnects.
final class HookServer {

    static let socketPath: String = {
        let dir = (NSHomeDirectory() as NSString)
            .appendingPathComponent("Library/Application Support/SlopIsland")
        return (dir as NSString).appendingPathComponent("hook.sock")
    }()

    static let permissionTimeoutSeconds: Double = 300

    private var serverSocket: Int32 = -1
    private var source: DispatchSourceRead?
    private var isRunning = false

    private let acceptQueue = DispatchQueue(label: "com.slopisland.hook.accept")
    private let clientQueue = DispatchQueue(label: "com.slopisland.hook.client", attributes: .concurrent)
    private let stateQueue = DispatchQueue(label: "com.slopisland.hook.state")

    /// sessionID -> open client fd awaiting a decision.
    private var pendingPermissions: [String: Int32] = [:]

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }

        ensureSocketDir()
        unlink(Self.socketPath)

        serverSocket = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverSocket >= 0 else {
            NSLog("[SlopIsland] socket() failed: \(errno)")
            return
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Self.socketPath.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            NSLog("[SlopIsland] socket path too long")
            close(serverSocket)
            return
        }
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dst in
                pathBytes.withUnsafeBufferPointer { src in
                    dst.update(from: src.baseAddress!, count: pathBytes.count)
                }
            }
        }

        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(serverSocket, $0, addrLen) }
        }
        guard bindResult == 0 else {
            NSLog("[SlopIsland] bind() failed: \(errno)")
            close(serverSocket)
            return
        }

        // Private to the user only.
        chmod(Self.socketPath, 0o700)

        guard listen(serverSocket, 10) == 0 else {
            NSLog("[SlopIsland] listen() failed: \(errno)")
            close(serverSocket)
            return
        }

        isRunning = true

        let src = DispatchSource.makeReadSource(fileDescriptor: serverSocket, queue: acceptQueue)
        src.setEventHandler { [weak self] in self?.acceptConnection() }
        src.setCancelHandler { [weak self] in
            if let fd = self?.serverSocket, fd >= 0 { close(fd) }
        }
        source = src
        src.resume()
        NSLog("[SlopIsland] HookServer listening at \(Self.socketPath)")
    }

    func stop() {
        isRunning = false
        source?.cancel()
        source = nil
        stateQueue.sync {
            for fd in pendingPermissions.values { close(fd) }
            pendingPermissions.removeAll()
        }
        unlink(Self.socketPath)
    }

    private func ensureSocketDir() {
        let dir = (Self.socketPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true, attributes: nil)
    }

    // MARK: - Accept / read

    private func acceptConnection() {
        let clientFd = accept(serverSocket, nil, nil)
        guard clientFd >= 0 else { return }
        // Never let a write to a disconnected client raise SIGPIPE (which would
        // kill the whole app). Deliver EPIPE on the syscall instead.
        var on: Int32 = 1
        setsockopt(clientFd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        clientQueue.async { [weak self] in self?.handleClient(clientFd) }
    }

    private func handleClient(_ clientFd: Int32) {
        var data = Data()
        var buf = [UInt8](repeating: 0, count: 8192)
        while true {
            let n = read(clientFd, &buf, buf.count)
            if n > 0 {
                data.append(contentsOf: buf[0..<n])
            } else {
                break // EOF (client did shutdown(SHUT_WR)) or error
            }
        }

        guard
            let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let event = HookEvent(raw: raw)
        else {
            close(clientFd)
            return
        }

        if event.status == "waiting_for_approval" {
            if event.isAskUserQuestion {
                // AskUserQuestion is a multiple-choice prompt, not an allow/deny
                // gate. Let Claude keep its own TUI (respond "ask"), unblock the
                // hook immediately, and surface the options in the notch; the
                // click injects the chosen number via KeySender.
                if let question = event.parseQuestion() {
                    DispatchQueue.main.async {
                        SessionStore.shared.process(.questionReceived(question))
                    }
                }
                writeDecision(fd: clientFd, decision: "ask")
                close(clientFd)
            } else {
                handlePermission(event: event, clientFd: clientFd)
            }
        } else {
            DispatchQueue.main.async { SessionStore.shared.process(.hookReceived(event)) }
            close(clientFd)
        }
    }

    // MARK: - Permission lifecycle

    private func handlePermission(event: HookEvent, clientFd: Int32) {
        let key = event.sessionID

        stateQueue.sync {
            // Replace any stale pending connection for the same session.
            if let old = pendingPermissions[key], old != clientFd {
                close(old)
            }
            pendingPermissions[key] = clientFd
        }

        DispatchQueue.main.async { SessionStore.shared.process(.hookReceived(event)) }

        // Safety timeout: if the user never decides, close the fd so Claude's
        // own UI takes over and we don't leak the descriptor.
        stateQueue.asyncAfter(deadline: .now() + Self.permissionTimeoutSeconds) { [weak self] in
            guard let self = self else { return }
            if let fd = self.pendingPermissions[key], fd == clientFd {
                self.pendingPermissions.removeValue(forKey: key)
                close(fd)
                DispatchQueue.main.async {
                    SessionStore.shared.process(.permissionTimedOut(sessionID: key))
                }
            }
        }
    }

    /// Called by the store when the user approves or denies.
    /// `decision` is "allow" / "deny" / "ask".
    func respond(sessionID: String, decision: String, reason: String = "") {
        stateQueue.async { [weak self] in
            guard let self = self,
                  let fd = self.pendingPermissions.removeValue(forKey: sessionID)
            else { return }
            self.writeDecision(fd: fd, decision: decision, reason: reason)
            close(fd) // EOF tells the python client the response is complete
        }
    }

    private func writeDecision(fd: Int32, decision: String, reason: String = "") {
        var payload: [String: Any] = ["decision": decision]
        if !reason.isEmpty { payload["reason"] = reason }
        if let data = try? JSONSerialization.data(withJSONObject: payload) {
            data.withUnsafeBytes { ptr in
                if let base = ptr.baseAddress {
                    _ = write(fd, base, data.count)
                }
            }
        }
    }
}
