import Foundation

enum SessionEvent {
    case hookReceived(HookEvent)
    case permissionApproved(sessionID: String)
    case permissionDenied(sessionID: String)
    case permissionTimedOut(sessionID: String)
    case questionAnswered(sessionID: String, answer: String)
    case questionReceived(UserQuestion)
    case activityDetected(sessionID: String, action: String, projectDir: String, projectName: String, cwd: String)
    case sessionEnded(sessionID: String)
    case sessionIdle(sessionID: String)

    var sessionID: String {
        switch self {
        case .hookReceived(let e): return e.sessionID
        case .permissionApproved(let id): return id
        case .permissionDenied(let id): return id
        case .permissionTimedOut(let id): return id
        case .questionAnswered(let id, _): return id
        case .questionReceived(let q): return q.sessionID
        case .activityDetected(let id, _, _, _, _): return id
        case .sessionEnded(let id): return id
        case .sessionIdle(let id): return id
        }
    }
}

/// One hook event decoded from `slopisland-hook.py`'s private JSON protocol.
struct HookEvent {
    let event: String          // PermissionRequest / UserPromptSubmit / Stop / ...
    let status: String         // waiting_for_approval / processing / ended / idle / waiting_for_input
    let sessionID: String
    let cwd: String
    let transcriptPath: String
    let toolName: String
    let toolInput: [String: Any]
    let message: String

    init?(raw: [String: Any]) {
        guard let sessionID = raw["session_id"] as? String, !sessionID.isEmpty else { return nil }
        self.sessionID = sessionID
        self.event = raw["event"] as? String ?? ""
        self.status = raw["status"] as? String ?? ""
        self.cwd = raw["cwd"] as? String ?? ""
        self.transcriptPath = raw["transcript_path"] as? String ?? ""
        self.toolName = raw["tool_name"] as? String ?? ""
        self.toolInput = raw["tool_input"] as? [String: Any] ?? [:]
        self.message = raw["message"] as? String ?? ""
    }

    /// Short single-line summary of the tool input for display.
    var toolInputSummary: String {
        if let cmd = toolInput["command"] as? String { return cmd }
        if let path = toolInput["file_path"] as? String { return path }
        if let urls = toolInput["urlList"] as? [String] { return urls.joined(separator: ", ") }
        if let query = toolInput["query"] as? String { return query }
        return ""
    }

    /// AskUserQuestion arrives as a PermissionRequest but is semantically a
    /// multiple-choice prompt, not an allow/deny gate.
    var isAskUserQuestion: Bool { toolName == "AskUserQuestion" }

    /// Parse the AskUserQuestion structure into a UserQuestion holding every
    /// bundled question (Claude can ask several at once).
    func parseQuestion() -> UserQuestion? {
        guard let questions = toolInput["questions"] as? [[String: Any]],
              !questions.isEmpty else { return nil }
        let items: [QuestionItem] = questions.compactMap { q in
            guard let prompt = q["question"] as? String else { return nil }
            let rawOptions = q["options"] as? [[String: Any]] ?? []
            let options = rawOptions.map { opt in
                QuestionOption(
                    label: opt["label"] as? String ?? "",
                    description: opt["description"] as? String
                )
            }
            return QuestionItem(
                header: q["header"] as? String ?? "",
                prompt: prompt,
                options: options,
                multiSelect: q["multiSelect"] as? Bool ?? false
            )
        }
        guard !items.isEmpty else { return nil }
        return UserQuestion(sessionID: sessionID, cwd: cwd, items: items)
    }

    /// Project display name derived from cwd.
    var projectName: String {        let name = (cwd as NSString).lastPathComponent
        return name.isEmpty ? "project" : name
    }
}

/// One line of a Claude Code transcript (`.jsonl`). Only the fields the monitor
/// reads are modeled; unknown keys are ignored. Decoding is lenient where the
/// format varies: `message.content` is a plain string in some user records and
/// an array of blocks elsewhere, so it decodes to `nil` rather than failing the
/// whole record.
struct TranscriptRecord: Decodable {
    let type: String?
    let subtype: String?
    let cwd: String?
    let message: Message?

    struct Message: Decodable {
        let content: [ContentBlock]?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            content = try? container.decode([ContentBlock].self, forKey: .content)
        }
        enum CodingKeys: String, CodingKey { case content }
    }

    struct ContentBlock: Decodable {
        let type: String?
        let name: String?
        let input: ToolInput?
    }

    /// Only the tool-input fields used to describe an action. Other tools carry
    /// no extra detail, so no other keys are needed.
    struct ToolInput: Decodable {
        let command: String?
        let filePath: String?
        enum CodingKeys: String, CodingKey {
            case command
            case filePath = "file_path"
        }
    }

    /// Decode one transcript line; returns nil for blank lines or records that
    /// don't parse (same skip behavior the monitor had with raw dictionaries).
    static func decode(line: String) -> TranscriptRecord? {
        guard !line.isEmpty, let data = line.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(TranscriptRecord.self, from: data)
    }

    /// The first meaningful content block in an assistant message: a tool use
    /// (with its tool name) or a text/thinking block. Drives the activity label.
    var firstAssistantBlock: ContentBlock? {
        guard type == "assistant" else { return nil }
        return message?.content?.first { $0.type == "tool_use" || $0.type == "text" }
    }
}

struct SessionState: Equatable, Identifiable {
    let sessionID: String
    let projectDir: String
    let projectName: String
    var phase: SessionPhase
    var lastActivity: Date
    /// Full jsonl path when known (from hook transcript_path); empty otherwise.
    var transcriptPath: String = ""
    /// Real absolute working directory of the session (from hook/transcript
    /// `cwd`); empty until known. Used to focus the exact terminal tab — the
    /// encoded `projectDir` ("/" -> "-") is lossy and can't be matched against a
    /// terminal's real working directory.
    var cwd: String = ""

    var id: String { sessionID }

    var displayTitle: String {
        SessionMetadataManager.shared.name(for: sessionID) ?? projectName
    }

    var jsonlPath: String {
        if !transcriptPath.isEmpty { return transcriptPath }
        let base = AppPaths.projectsDir
        return "\(base)/\(projectDir)/\(sessionID).jsonl"
    }

    static func == (lhs: SessionState, rhs: SessionState) -> Bool {
        lhs.sessionID == rhs.sessionID
            && lhs.phase == rhs.phase
            && lhs.lastActivity == rhs.lastActivity
    }
}

// MARK: - Pure state transitions
//
// These are side-effect-free reducers over the session map: same inputs always
// produce the same output, no singletons / timers / sockets involved. SessionStore
// drives the actual side effects (socket replies, key injection, removal timers)
// around them. Kept pure so the state machine can be unit-tested in isolation.
extension SessionState {

    /// Insert a session if absent, or backfill its transcript path once known.
    /// Returns the new map (never mutates the input).
    static func ensuring(
        _ sessions: [String: SessionState],
        id: String,
        projectDir: String,
        projectName: String,
        transcriptPath: String = "",
        cwd: String = "",
        now: Date
    ) -> [String: SessionState] {
        var next = sessions
        if let existing = next[id] {
            // Backfill the transcript path and/or cwd once we learn them.
            let needsTranscript = existing.transcriptPath.isEmpty && !transcriptPath.isEmpty
            let needsCwd = existing.cwd.isEmpty && !cwd.isEmpty
            if needsTranscript || needsCwd {
                next[id] = SessionState(
                    sessionID: existing.sessionID,
                    projectDir: existing.projectDir,
                    projectName: existing.projectName,
                    phase: existing.phase,
                    lastActivity: existing.lastActivity,
                    transcriptPath: needsTranscript ? transcriptPath : existing.transcriptPath,
                    cwd: needsCwd ? cwd : existing.cwd
                )
            }
            return next
        }
        next[id] = SessionState(
            sessionID: id,
            projectDir: projectDir,
            projectName: projectName.isEmpty ? "project" : projectName,
            phase: .idle,
            lastActivity: now,
            transcriptPath: transcriptPath,
            cwd: cwd
        )
        return next
    }

    /// Advance a session's phase if the transition is allowed by `canTransition`.
    /// Returns the new map plus whether a change actually happened (so the store
    /// knows whether to notify observers / schedule removal).
    static func applyingPhase(
        _ sessions: [String: SessionState],
        id: String,
        phase: SessionPhase,
        now: Date
    ) -> (sessions: [String: SessionState], changed: Bool) {
        guard let session = sessions[id] else { return (sessions, false) }
        guard session.phase.canTransition(to: phase) else { return (sessions, false) }
        var next = sessions
        next[id] = SessionState(
            sessionID: session.sessionID,
            projectDir: session.projectDir,
            projectName: session.projectName,
            phase: phase,
            lastActivity: now,
            transcriptPath: session.transcriptPath,
            cwd: session.cwd
        )
        return (next, true)
    }

    /// Whether an ended session is still eligible for removal after its grace
    /// period: it must still be `.ended` and not have been reactivated (its
    /// `lastActivity` timestamp unchanged since it ended).
    static func shouldRemoveEnded(_ session: SessionState, endedAt: Date?) -> Bool {
        guard case .ended = session.phase else { return false }
        return session.lastActivity == endedAt
    }
}
