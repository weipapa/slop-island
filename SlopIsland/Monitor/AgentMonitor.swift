import AppKit
import CoreServices

final class AgentMonitor {

    private let projectsDir = NSString(string: "~/.codefuse/engine/cc/projects").expandingTildeInPath
    private var watchedFiles: [String: UInt64] = [:]
    private var sessionStartTimes: [String: Date] = [:]

    private var isRunning = false
    private var idleTimer: Timer?
    private var eventStream: FSEventStreamRef?

    /// FSEvents C callback: trampolines back to the owning monitor. Captures
    /// nothing so it converts to a `@convention(c)` pointer.
    private let eventCallback: FSEventStreamCallback = { _, info, count, pathsPtr, flagsPtr, _ in
        guard let info = info else { return }
        let monitor = Unmanaged<AgentMonitor>.fromOpaque(info).takeUnretainedValue()
        let paths = unsafeBitCast(pathsPtr, to: NSArray.self) as? [String] ?? []
        let flags = (0..<count).map { flagsPtr[$0] }
        monitor.handleEvents(paths: paths, flags: flags)
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true

        // Drop per-session caches when the store recycles a session, so our
        // dictionaries don't grow without bound.
        SessionStore.shared.observeRemoval { [weak self] sessionID in
            guard let self = self else { return }
            self.sessionStartTimes.removeValue(forKey: sessionID)
            let suffix = "/\(sessionID).jsonl"
            for path in self.watchedFiles.keys where path.hasSuffix(suffix) {
                self.watchedFiles.removeValue(forKey: path)
            }
        }

        scanExistingSessions()
        startEventStream()
    }

    func stop() {
        isRunning = false
        if let stream = eventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            eventStream = nil
        }
        idleTimer?.invalidate()
    }

    /// Watch the projects directory for file-level changes instead of polling
    /// the whole tree every second. Callbacks are delivered on the main queue,
    /// matching the threading the rest of this class (and SessionStore) assume.
    private func startEventStream() {
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let flags = UInt32(
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagNoDefer |
            kFSEventStreamCreateFlagUseCFTypes
        )
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            eventCallback,
            &context,
            [projectsDir] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3,
            flags
        ) else { return }

        eventStream = stream
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
    }

    /// Process only the files FSEvents reported as changed.
    private func handleEvents(paths: [String], flags: [FSEventStreamEventFlags]) {
        let now = Date()
        var foundActive = false

        for (i, path) in paths.enumerated() {
            guard path.hasSuffix(".jsonl") else { continue }
            let url = URL(fileURLWithPath: path)
            guard url.deletingLastPathComponent().lastPathComponent != "subagents" else { continue }

            let removed = i < flags.count
                && (flags[i] & FSEventStreamEventFlags(kFSEventStreamEventFlagItemRemoved)) != 0
            if removed, !FileManager.default.fileExists(atPath: path) {
                watchedFiles.removeValue(forKey: path)
                continue
            }

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

    /// Read only the tail of the file (transcripts can be multiple MB) and find
    /// the most recent meaningful action.
    private func readLastAction(path: String) -> String? {
        guard let text = tail(path: path, maxBytes: 256 * 1024) else { return nil }

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

    /// Read up to the last `maxBytes` of a file as UTF-8, dropping a leading
    /// partial line so JSON parsing never sees a truncated record.
    private func tail(path: String, maxBytes: UInt64) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { handle.closeFile() }

        let size = handle.seekToEndOfFile()
        let offset = size > maxBytes ? size - maxBytes : 0
        handle.seek(toFileOffset: offset)
        let data = handle.readDataToEndOfFile()
        guard var text = String(data: data, encoding: .utf8) else { return nil }

        if offset > 0, let firstNewline = text.firstIndex(of: "\n") {
            text = String(text[text.index(after: firstNewline)...])
        }
        return text
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

        // The hook stream is authoritative for permission/question prompts.
        // Never let file-polled activity overwrite a session that's waiting on
        // the user (would make the permission UI vanish).
        if store.sessions[sessionId]?.phase.needsAttention == true,
           !(type == "system") {
            return
        }

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
                // Don't mark a session idle while it's waiting on the user.
                if SessionStore.shared.sessions[sessionId]?.phase.needsAttention == true { continue }
                SessionStore.shared.process(.sessionIdle(sessionID: sessionId))
            }
        }
    }
}
