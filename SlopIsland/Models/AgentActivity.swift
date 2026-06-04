import Foundation

enum AgentActivity {
    case running(action: String)
    case waiting
    case idle

    var label: String {
        switch self {
        case .running(let action): return action
        case .waiting: return "awaiting input"
        case .idle: return "idle"
        }
    }
}
