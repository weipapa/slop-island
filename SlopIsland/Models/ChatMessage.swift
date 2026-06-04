import Foundation

struct ChatHistoryItem: Identifiable {
    let id: String
    let type: ChatItemType
    let timestamp: Date

    enum ChatItemType {
        case user(String)
        case assistant(String)
        case toolCall(name: String, input: String, status: ToolCallStatus)
        case thinking(String)
    }

    enum ToolCallStatus {
        case running
        case success
        case error
    }
}
