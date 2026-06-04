import Foundation

final class HookServer {

    private let socketPath = "/tmp/circleask-claude.sock"
    private var serverSocket: Int32 = -1
    private var source: DispatchSourceRead?
    private var isRunning = false

    func start() {
        guard !isRunning else { return }

        unlink(socketPath)

        serverSocket = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverSocket >= 0 else { return }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            let raw = UnsafeMutableRawPointer(ptr)
            pathBytes.withUnsafeBufferPointer { buf in
                raw.copyMemory(from: buf.baseAddress!, byteCount: min(buf.count, 104))
            }
        }

        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                _ = bind(serverSocket, sockPtr, addrLen)
            }
        }

        listen(serverSocket, 5)
        isRunning = true

        source = DispatchSource.makeReadSource(fileDescriptor: serverSocket, queue: .main)
        source?.setEventHandler { [weak self] in
            self?.acceptConnection()
        }
        source?.setCancelHandler { [weak self] in
            if let fd = self?.serverSocket, fd >= 0 {
                close(fd)
            }
        }
        source?.resume()
    }

    func stop() {
        isRunning = false
        source?.cancel()
        source = nil
        unlink(socketPath)
    }

    private func acceptConnection() {
        let clientFd = accept(serverSocket, nil, nil)
        guard clientFd >= 0 else { return }

        DispatchQueue.global(qos: .userInteractive).async {
            var data = Data()
            var buf = [UInt8](repeating: 0, count: 8192)
            while true {
                let n = read(clientFd, &buf, buf.count)
                if n <= 0 { break }
                data.append(contentsOf: buf[0..<n])
                if n < buf.count { break }
            }

            guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                close(clientFd)
                return
            }

            let eventType = raw["eventType"] as? String ?? ""
            let toolName = raw["title"] as? String ?? ""
            let metadata = raw["metadata"] as? [String: Any] ?? [:]
            let sessionID = (metadata["session_id"] as? String) ?? ""
            let permissionMode = (metadata["permission_mode"] as? String) ?? "auto"
            let cwd = (raw["cwd"] as? String) ?? "~"
            let expectsResponse = raw["expectsResponse"] as? Bool ?? false

            var toolInputDict: [String: Any] = [:]
            if let previewStr = raw["preview"] as? String,
               let previewData = previewStr.data(using: .utf8),
               let previewJSON = try? JSONSerialization.jsonObject(with: previewData) as? [String: Any] {
                toolInputDict = previewJSON
            }

            let inputStr = (toolInputDict["command"] as? String)
                ?? (toolInputDict["file_path"] as? String)
                ?? ""

            DispatchQueue.main.async {
                let store = SessionStore.shared

                if toolName == "AskUserQuestion" {
                    let question = Self.parseQuestion(from: toolInputDict, sessionID: sessionID, cwd: cwd)
                    if let question = question {
                        store.process(.questionReceived(question))
                        if expectsResponse {
                            store.setPermissionResponder(sessionID: sessionID) { decision in
                                let response: [String: Any] = ["decision": decision]
                                if let responseData = try? JSONSerialization.data(withJSONObject: response) {
                                    _ = responseData.withUnsafeBytes { ptr in
                                        write(clientFd, ptr.baseAddress!, responseData.count)
                                    }
                                }
                                close(clientFd)
                            }
                        } else {
                            close(clientFd)
                        }
                        return
                    }
                }

                if eventType == "PreToolUse" && sessionID.isEmpty == false {
                    let payload = HookPayload(
                        sessionID: sessionID,
                        cwd: cwd,
                        eventName: eventType,
                        toolName: toolName,
                        toolInput: inputStr,
                        permissionMode: expectsResponse ? "ask" : "auto",
                        expectsResponse: expectsResponse,
                        rawInput: toolInputDict
                    )
                    store.process(.hookReceived(payload))

                    if expectsResponse && permissionMode != "auto" {
                        store.setPermissionResponder(sessionID: sessionID) { decision in
                            let response: [String: Any] = ["decision": decision]
                            if let responseData = try? JSONSerialization.data(withJSONObject: response) {
                                _ = responseData.withUnsafeBytes { ptr in
                                    write(clientFd, ptr.baseAddress!, responseData.count)
                                }
                            }
                            close(clientFd)
                        }
                    } else {
                        close(clientFd)
                    }
                } else {
                    close(clientFd)
                }
            }
        }
    }

    private static func parseQuestion(from input: [String: Any], sessionID: String, cwd: String) -> UserQuestion? {
        guard let questions = input["questions"] as? [[String: Any]],
              let first = questions.first,
              let questionText = first["question"] as? String else { return nil }

        var options: [QuestionOption] = []
        if let rawOptions = first["options"] as? [[String: Any]] {
            for opt in rawOptions {
                let label = opt["label"] as? String ?? ""
                let desc = opt["description"] as? String
                options.append(QuestionOption(label: label, description: desc))
            }
        }

        return UserQuestion(sessionID: sessionID, cwd: cwd, question: questionText, options: options)
    }
}
