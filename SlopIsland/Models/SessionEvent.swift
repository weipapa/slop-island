import Foundation

enum SessionEvent {
    case hookReceived(HookPayload)
    case permissionApproved(sessionID: String)
    case permissionDenied(sessionID: String)
    case questionAnswered(sessionID: String, answer: String)
    case questionReceived(UserQuestion)
    case activityDetected(sessionID: String, action: String, projectDir: String, projectName: String)
    case sessionEnded(sessionID: String)
    case sessionIdle(sessionID: String)

    var sessionID: String {
        switch self {
        case .hookReceived(let p): return p.sessionID
        case .permissionApproved(let id): return id
        case .permissionDenied(let id): return id
        case .questionAnswered(let id, _): return id
        case .questionReceived(let q): return q.sessionID
        case .activityDetected(let id, _, _, _): return id
        case .sessionEnded(let id): return id
        case .sessionIdle(let id): return id
        }
    }
}

struct HookPayload {
    let sessionID: String
    let cwd: String
    let eventName: String
    let toolName: String
    let toolInput: String
    let permissionMode: String
    let expectsResponse: Bool
    let rawInput: [String: Any]
}

struct SessionState: Equatable, Identifiable {
    let sessionID: String
    let projectDir: String
    let projectName: String
    var phase: SessionPhase
    var lastActivity: Date

    var id: String { sessionID }

    var displayTitle: String {
        SessionMetadataManager.shared.name(for: sessionID) ?? projectName
    }

    var jsonlPath: String {
        let base = NSString(string: "~/.codefuse/engine/cc/projects").expandingTildeInPath
        return "\(base)/\(projectDir)/\(sessionID).jsonl"
    }

    static func == (lhs: SessionState, rhs: SessionState) -> Bool {
        lhs.sessionID == rhs.sessionID
            && lhs.phase == rhs.phase
            && lhs.lastActivity == rhs.lastActivity
    }
}
