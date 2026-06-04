import AppKit

final class AgentMonitor {

    private let projectsDir = NSString(string: "~/.codefuse/engine/cc/projects").expandingTildeInPath
    private var watchedFiles: [String: UInt64] = [:]
    private var pollTimer: Timer?
    private var sessionStartTimes: [String: Date] = [:]

    private var isRunning = false
    private var idleTimer: Timer?

    func start() {
        guard !isRunning else { return }
        isRunning = true

        scanExistingSessions()

        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.pollActiveFiles()
        }
    }

    func stop() {
        isRunning = false
        pollTimer?.invalidate()
        pollTimer = nil
        idleTimer?.invalidate()
    }

    private func scanExistingSessions() {
        guard let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: projectsDir),
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let now = Date()
        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension == "jsonl" else { continue }
            let path = url.path
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
                  let modDate = attrs[.modificationDate] as? Date,
                  now.timeIntervalSince(modDate) < 300 else { continue }

            let parentDir = url.deletingLastPathComponent().lastPathComponent
            guard parentDir != "subagents" else { continue }

            let sessionId = url.deletingPathExtension().lastPathComponent
            let projectDir = parentDir
            let projectName = projectDir
                .replacingOccurrences(of: "-Users-lpw-", with: "")
                .replacingOccurrences(of: "-", with: "/")

            sessionStartTimes[sessionId] = modDate

            let lastAction = readLastAction(path: path)
            let store = SessionStore.shared
            store.process(.activityDetected(
                sessionID: sessionId,
                action: lastAction ?? "idle",
                projectDir: projectDir,
                projectName: projectName
            ))

            let currentSize = (attrs[.size] as? UInt64) ?? 0
            watchedFiles[path] = currentSize
        }
    }

    private func readLastAction(path: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path),
              let text = String(data: data, encoding: .utf8) else { return nil }

        let lines = text.components(separatedBy: "\n").reversed()
        for line in lines {
            guard !line.isEmpty,
                  let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else { continue }

            let type = json["type"] as? String ?? ""
            if type == "assistant",
               let message = json["message"] as? [String: Any],
               let content = message["content"] as? [[String: Any]] {
                for block in content {
                    if block["type"] as? String == "tool_use" {
                        let toolName = block["name"] as? String ?? ""
                        let input = block["input"] as? [String: Any] ?? [:]
                        let detail = (input["command"] as? String)
                            ?? (input["file_path"] as? String).map { ($0 as NSString).lastPathComponent }
                            ?? ""
                        return "\(toolName) \(detail)".trimmingCharacters(in: .whitespaces)
                    }
                    if block["type"] as? String == "text" {
                        return "thinking"
                    }
                }
            }
        }
        return nil
    }

    private func pollActiveFiles() {
        guard let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: projectsDir),
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let now = Date()
        var foundActive = false

        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension == "jsonl" else { continue }
            guard url.deletingLastPathComponent().lastPathComponent != "subagents" else { continue }

            let path = url.path
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
                  let modDate = attrs[.modificationDate] as? Date,
                  now.timeIntervalSince(modDate) < 300 else { continue }

            foundActive = true
            let currentSize = (attrs[.size] as? UInt64) ?? 0
            let lastSize = watchedFiles[path] ?? currentSize

            if currentSize > lastSize {
                readNewContent(path: path, from: lastSize, to: currentSize)
            }
            watchedFiles[path] = currentSize
        }

        if foundActive {
            resetIdleTimer()
        }
    }

    private func readNewContent(path: String, from: UInt64, to: UInt64) {
        guard let handle = FileHandle(forReadingAtPath: path) else { return }
        defer { handle.closeFile() }

        handle.seek(toFileOffset: from)
        let data = handle.readData(ofLength: Int(to - from))
        guard let text = String(data: data, encoding: .utf8) else { return }

        let sessionId = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        let projectDir = URL(fileURLWithPath: path).deletingLastPathComponent().lastPathComponent
        let projectName = projectDir
            .replacingOccurrences(of: "-Users-lpw-", with: "")
            .replacingOccurrences(of: "-", with: "/")

        if sessionStartTimes[sessionId] == nil {
            sessionStartTimes[sessionId] = Date()
        }

        for line in text.components(separatedBy: "\n") where !line.isEmpty {
            guard let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else { continue }

            processJsonlEntry(json, sessionId: sessionId, projectDir: projectDir, projectName: projectName)
        }
    }

    private func processJsonlEntry(_ json: [String: Any], sessionId: String, projectDir: String, projectName: String) {
        let type = json["type"] as? String ?? ""
        let store = SessionStore.shared
        let elapsed = formatDuration(since: sessionStartTimes[sessionId] ?? Date())

        switch type {
        case "assistant":
            guard let message = json["message"] as? [String: Any],
                  let content = message["content"] as? [[String: Any]] else { return }

            for block in content {
                let blockType = block["type"] as? String ?? ""
                if blockType == "tool_use" {
                    let toolName = block["name"] as? String ?? ""
                    let input = block["input"] as? [String: Any] ?? [:]
                    let action = actionDescription(tool: toolName, input: input, elapsed: elapsed)
                    store.process(.activityDetected(sessionID: sessionId, action: action, projectDir: projectDir, projectName: projectName))
                    return
                } else if blockType == "text" {
                    store.process(.activityDetected(
                        sessionID: sessionId,
                        action: "thinking \u{00B7} \(elapsed)",
                        projectDir: projectDir,
                        projectName: projectName
                    ))
                    return
                }
            }

        case "user":
            guard let message = json["message"] as? [String: Any],
                  let content = message["content"] as? [[String: Any]] else { return }

            for block in content {
                let blockType = block["type"] as? String ?? ""
                if blockType == "tool_result" {
                    store.process(.activityDetected(
                        sessionID: sessionId,
                        action: "thinking \u{00B7} \(elapsed)",
                        projectDir: projectDir,
                        projectName: projectName
                    ))
                    return
                }
            }

        case "system":
            let subtype = json["subtype"] as? String ?? ""
            if subtype == "stop" || subtype == "stop_hook_summary" {
                sessionStartTimes[sessionId] = nil
                store.process(.sessionEnded(sessionID: sessionId))
            }

        default:
            break
        }
    }

    private func actionDescription(tool: String, input: [String: Any], elapsed: String) -> String {
        let detail: String
        switch tool {
        case "Bash":
            let cmd = (input["command"] as? String) ?? ""
            detail = "\u{25B6} \(String(cmd.prefix(30)))"
        case "Write":
            let file = (input["file_path"] as? String) ?? "file"
            detail = "\u{270E} \((file as NSString).lastPathComponent)"
        case "Edit":
            let file = (input["file_path"] as? String) ?? "file"
            detail = "\u{270E} \((file as NSString).lastPathComponent)"
        case "Read":
            let file = (input["file_path"] as? String) ?? "file"
            detail = "\u{25C9} \((file as NSString).lastPathComponent)"
        case "Grep", "Glob":
            detail = "\u{2315} searching"
        case "Agent":
            detail = "\u{25C6} subagent"
        default:
            detail = tool.lowercased()
        }
        return "\(detail) \u{00B7} \(elapsed)"
    }

    private func formatDuration(since start: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(start))
        if seconds < 60 {
            return "\(seconds)s"
        }
        let m = seconds / 60
        let s = seconds % 60
        return "\(m)m \(s)s"
    }

    private func resetIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            for sessionId in self.sessionStartTimes.keys {
                SessionStore.shared.process(.sessionIdle(sessionID: sessionId))
            }
        }
    }
}
