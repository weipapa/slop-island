import Foundation

struct PermissionContext: Equatable {
    let toolUseID: String
    let toolName: String
    let toolInput: String
    let receivedAt: Date
}

enum SessionPhase: Equatable {
    case idle
    case processing(action: String)
    case waitingForApproval(PermissionContext)
    case waitingForQuestion(UserQuestion)
    case ended

    var needsAttention: Bool {
        switch self {
        case .waitingForApproval, .waitingForQuestion: return true
        default: return false
        }
    }

    var isActive: Bool {
        if case .processing = self { return true }
        return false
    }

    func canTransition(to next: SessionPhase) -> Bool {
        if self == next { return true }
        // Any phase may end.
        if case .ended = next { return true }

        switch self {
        case .idle:
            return true
        case .processing:
            return true
        case .waitingForApproval:
            // Only an explicit resolution (continue/idle), end, or a switch to
            // the other attention state may clear an approval prompt. Plain
            // activity must NOT clobber it.
            switch next {
            case .processing, .idle, .waitingForQuestion:
                return true
            default:
                return false
            }
        case .waitingForQuestion:
            switch next {
            case .processing, .idle, .waitingForApproval:
                return true
            default:
                return false
            }
        case .ended:
            // A previously ended session reactivates when genuine new activity
            // arrives (the same sessionID is reused after the user keeps going).
            switch next {
            case .processing, .waitingForApproval, .waitingForQuestion:
                return true
            case .idle:
                return false
            default:
                return false
            }
        }
    }

    static func == (lhs: SessionPhase, rhs: SessionPhase) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.ended, .ended): return true
        case (.processing(let a), .processing(let b)): return a == b
        case (.waitingForApproval(let a), .waitingForApproval(let b)): return a == b
        case (.waitingForQuestion(let a), .waitingForQuestion(let b)): return a.sessionID == b.sessionID && a.items.count == b.items.count
        default: return false
        }
    }
}
