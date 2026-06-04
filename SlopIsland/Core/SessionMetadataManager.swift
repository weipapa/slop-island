import SwiftUI
import Observation

@Observable
final class SessionMetadataManager {
    static let shared = SessionMetadataManager()
    private init() { loadFromDefaults() }

    private(set) var sessionColors: [String: String] = [:]
    private(set) var sessionNames: [String: String] = [:]

    func color(for sessionID: String) -> Color? {
        guard let hex = sessionColors[sessionID] else { return nil }
        return Color(hex: hex)
    }

    func name(for sessionID: String) -> String? {
        sessionNames[sessionID]
    }

    func setColor(_ hex: String?, for sessionID: String) {
        if let hex = hex {
            sessionColors[sessionID] = hex
        } else {
            sessionColors.removeValue(forKey: sessionID)
        }
        saveColors()
    }

    func setName(_ name: String?, for sessionID: String) {
        let trimmed = name?.trimmingCharacters(in: .whitespaces)
        if let trimmed = trimmed, !trimmed.isEmpty {
            sessionNames[sessionID] = trimmed
        } else {
            sessionNames.removeValue(forKey: sessionID)
        }
        saveNames()
    }

    private func loadFromDefaults() {
        if let data = UserDefaults.standard.data(forKey: "sessionColors"),
           let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            sessionColors = dict
        }
        if let data = UserDefaults.standard.data(forKey: "sessionNames"),
           let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            sessionNames = dict
        }
    }

    private func saveColors() {
        if let data = try? JSONEncoder().encode(sessionColors) {
            UserDefaults.standard.set(data, forKey: "sessionColors")
        }
    }

    private func saveNames() {
        if let data = try? JSONEncoder().encode(sessionNames) {
            UserDefaults.standard.set(data, forKey: "sessionNames")
        }
    }
}

extension Color {
    init?(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let val = UInt64(h, radix: 16) else { return nil }
        self.init(
            red: Double((val >> 16) & 0xFF) / 255,
            green: Double((val >> 8) & 0xFF) / 255,
            blue: Double(val & 0xFF) / 255
        )
    }
}
