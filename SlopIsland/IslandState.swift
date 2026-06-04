import Foundation

enum IslandState {
    case idle
    case compact(session: SessionState)
    case expandedPermission(session: SessionState, context: PermissionContext)
    case done(session: SessionState)
    case expandedList(sessions: [SessionState])

    var belowHeight: CGFloat {
        switch self {
        case .idle: return 0
        case .compact, .done: return 48
        case .expandedPermission: return 150
        case .expandedList(let sessions):
            let count = CGFloat(max(sessions.count, 1))
            let raw = count * 42 + max(0, count - 1) * 2
            return min(raw, 350)
        }
    }

    var width: CGFloat {
        switch self {
        case .idle: return 185
        case .compact, .done: return 300
        case .expandedPermission: return 360
        case .expandedList: return 480
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .idle: return 0
        case .compact, .done: return 18
        case .expandedPermission, .expandedList: return 22
        }
    }

    static func from(session: SessionState) -> IslandState {
        switch session.phase {
        case .idle:
            return .idle
        case .processing:
            return .compact(session: session)
        case .waitingForApproval(let ctx):
            return .expandedPermission(session: session, context: ctx)
        case .ended:
            return .done(session: session)
        }
    }
}
