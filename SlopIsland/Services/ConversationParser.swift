import Foundation

actor ConversationParser {
    static let shared = ConversationParser()

    func parse(jsonlPath: String) -> [ChatHistoryItem] {
        guard let data = FileManager.default.contents(atPath: jsonlPath),
              let text = String(data: data, encoding: .utf8) else { return [] }

        var items: [ChatHistoryItem] = []
        for line in text.components(separatedBy: "\n") where !line.isEmpty {
            guard let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else { continue }

            let type = json["type"] as? String ?? ""
            let uuid = json["uuid"] as? String ?? UUID().uuidString
            let ts = (json["timestamp"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date()

            switch type {
            case "user":
                if let text = extractUserText(json) {
                    items.append(ChatHistoryItem(id: uuid, type: .user(text), timestamp: ts))
                }
            case "assistant":
                items.append(contentsOf: extractAssistantBlocks(json, uuid: uuid, ts: ts))
            default:
                break
            }
        }
        return items
    }

    private func extractUserText(_ json: [String: Any]) -> String? {
        guard let message = json["message"] as? [String: Any],
              let content = message["content"] as? [[String: Any]] else { return nil }
        let texts = content.compactMap { block -> String? in
            guard block["type"] as? String == "text" else { return nil }
            return block["text"] as? String
        }
        return texts.isEmpty ? nil : texts.joined(separator: "\n")
    }

    private func extractAssistantBlocks(_ json: [String: Any], uuid: String, ts: Date) -> [ChatHistoryItem] {
        guard let message = json["message"] as? [String: Any],
              let content = message["content"] as? [[String: Any]] else { return [] }

        var items: [ChatHistoryItem] = []
        for (i, block) in content.enumerated() {
            let blockType = block["type"] as? String ?? ""
            let blockID = "\(uuid)-\(i)"

            switch blockType {
            case "text":
                if let text = block["text"] as? String, !text.isEmpty {
                    items.append(ChatHistoryItem(id: blockID, type: .assistant(text), timestamp: ts))
                }
            case "thinking":
                if let text = block["thinking"] as? String, !text.isEmpty {
                    items.append(ChatHistoryItem(id: blockID, type: .thinking(text), timestamp: ts))
                }
            case "tool_use":
                let name = block["name"] as? String ?? "tool"
                let input = block["input"] as? [String: Any] ?? [:]
                let inputStr = (input["command"] as? String)
                    ?? (input["file_path"] as? String)
                    ?? (input["query"] as? String)
                    ?? ""
                items.append(ChatHistoryItem(id: blockID, type: .toolCall(name: name, input: inputStr, status: .success), timestamp: ts))
            default:
                break
            }
        }
        return items
    }
}
