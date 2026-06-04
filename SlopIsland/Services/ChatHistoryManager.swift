import Foundation
import Observation

@Observable
final class ChatHistoryManager {
    static let shared = ChatHistoryManager()
    private init() {}

    private(set) var histories: [String: [ChatHistoryItem]] = [:]

    func loadHistory(jsonlPath: String, sessionID: String) async {
        let items = await ConversationParser.shared.parse(jsonlPath: jsonlPath)
        histories[sessionID] = items
    }

    func history(for sessionID: String) -> [ChatHistoryItem] {
        histories[sessionID] ?? []
    }
}
