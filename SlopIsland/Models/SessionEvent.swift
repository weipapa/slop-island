import Foundation

enum SessionEvent {
    case hookReceived(HookEvent)
    case permissionApproved(sessionID: String)
    case permissionDenied(sessionID: String)
    case permissionTimedOut(sessionID: String)
    case questionAnswered(sessionID: String, answer: String)
    case questionReceived(UserQuestion)
    case activityDetected(sessionID: String, action: String, projectDir: String, projectName: String)
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
        case .activityDetected(let id, _, _, _): return id
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

    /// Parse the AskUserQuestion structure into a UserQuestion (first question).
    func parseQuestion() -> UserQuestion? {
        guard let questions = toolInput["questions"] as? [[String: Any]],
              let first = questions.first,
              let text = first["question"] as? String else { return nil }
        let rawOptions = first["options"] as? [[String: Any]] ?? []
        let options = rawOptions.map { opt in
            QuestionOption(
                label: opt["label"] as? String ?? "",
                description: opt["description"] as? String
            )
        }
        return UserQuestion(sessionID: sessionID, cwd: cwd, question: text, options: options)
    }

    /// Project display name derived from cwd.
    var projectName: String {        let name = (cwd as NSString).lastPathComponent
        return name.isEmpty ? "project" : name
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

    var id: String { sessionID }

    var displayTitle: String {
        SessionMetadataManager.shared.name(for: sessionID) ?? projectName
    }

    var jsonlPath: String {
        if !transcriptPath.isEmpty { return transcriptPath }
        let base = NSString(string: "~/.codefuse/engine/cc/projects").expandingTildeInPath
        return "\(base)/\(projectDir)/\(sessionID).jsonl"
    }

    static func == (lhs: SessionState, rhs: SessionState) -> Bool {
        lhs.sessionID == rhs.sessionID
            && lhs.phase == rhs.phase
            && lhs.lastActivity == rhs.lastActivity
    }
}
