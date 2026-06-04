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
        if case .ended = self { return false }
        if case .ended = next { return true }
        if self == next { return true }

        switch self {
        case .idle:
            return true
        case .processing:
            return true
        case .waitingForApproval:
            switch next {
            case .processing, .idle, .ended:
                return true
            default:
                return false
            }
        case .waitingForQuestion:
            switch next {
            case .processing, .idle, .ended:
                return true
            default:
                return false
            }
        case .ended:
            return false
        }
    }

    static func == (lhs: SessionPhase, rhs: SessionPhase) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.ended, .ended): return true
        case (.processing(let a), .processing(let b)): return a == b
        case (.waitingForApproval(let a), .waitingForApproval(let b)): return a == b
        case (.waitingForQuestion(let a), .waitingForQuestion(let b)): return a.sessionID == b.sessionID && a.question == b.question
        default: return false
        }
    }
}
