import Foundation

enum AppSettings {
    static var notificationSoundEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "notificationSoundEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "notificationSoundEnabled") }
    }
}

/// Single source of truth for the Claude Code config locations. Honors
/// `CLAUDE_CONFIG_DIR` (the same override Claude Code itself uses) and falls
/// back to the default install path, so every component agrees on where the
/// settings and project transcripts live.
enum AppPaths {

    /// Claude Code's config directory: `$CLAUDE_CONFIG_DIR` or the default.
    static var configDir: String {
        if let dir = Foundation.ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !dir.isEmpty {
            return (dir as NSString).expandingTildeInPath
        }
        return (NSHomeDirectory() as NSString)
            .appendingPathComponent(".codefuse/engine/cc")
    }

    /// `settings.json` where hooks are registered.
    static var settingsPath: String {
        (configDir as NSString).appendingPathComponent("settings.json")
    }

    /// Root holding per-project session transcripts (`<project>/<session>.jsonl`).
    static var projectsDir: String {
        (configDir as NSString).appendingPathComponent("projects")
    }
}
