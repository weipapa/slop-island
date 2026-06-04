import Foundation

/// Installs SlopIsland's own hook into Claude Code, fully decoupled from circleask:
/// 1. copies the bundled `slopisland-hook.py` into Application Support,
/// 2. adds SlopIsland's command to the relevant events in settings.json,
///    touching only its own entries (other tools' hooks are preserved).
enum HookInstaller {

    private static let scriptName = "slopisland-hook.py"
    private static let marker = scriptName // any command containing this is "ours"

    /// Events we hook, and whether the hook blocks waiting for a decision.
    private static let events: [(name: String, blocking: Bool)] = [
        ("PermissionRequest", true),
        ("UserPromptSubmit", false),
        ("SessionStart", false),
        ("Notification", false),
        ("Stop", false),
        ("SessionEnd", false),
    ]

    static var supportDir: String {
        (NSHomeDirectory() as NSString)
            .appendingPathComponent("Library/Application Support/SlopIsland")
    }

    static var installedScriptPath: String {
        (supportDir as NSString).appendingPathComponent(scriptName)
    }

    static var settingsPath: String {
        if let dir = Foundation.ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !dir.isEmpty {
            return (dir as NSString).appendingPathComponent("settings.json")
        }
        return (NSHomeDirectory() as NSString)
            .appendingPathComponent(".codefuse/engine/cc/settings.json")
    }

    static func installIfNeeded() {
        do {
            try deployScript()
            let command = "\(pythonExecutable) '\(installedScriptPath)'"
            try updateSettings(command: command)
            NSLog("[SlopIsland] hook installed -> \(settingsPath)")
        } catch {
            NSLog("[SlopIsland] hook install failed: \(error)")
        }
    }

    // MARK: - Script deployment

    private static func deployScript() throws {
        try FileManager.default.createDirectory(
            atPath: supportDir, withIntermediateDirectories: true)

        guard let bundled = Bundle.main.url(forResource: "slopisland-hook", withExtension: "py") else {
            throw NSError(domain: "SlopIsland", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "bundled hook script missing"])
        }

        let dest = URL(fileURLWithPath: installedScriptPath)
        let tmp = dest.appendingPathExtension("tmp")
        let data = try Data(contentsOf: bundled)
        try data.write(to: tmp, options: .atomic)
        _ = try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmp, to: dest)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest.path)
    }

    /// Prefer an explicit python3.14, since the script requires >=3.14.
    private static var pythonExecutable: String {
        let candidates = [
            "/opt/homebrew/bin/python3.14",
            "/usr/local/bin/python3.14",
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return "/usr/bin/env python3.14"
    }

    // MARK: - settings.json

    private static func updateSettings(command: String) throws {
        let url = URL(fileURLWithPath: settingsPath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        try withFileLock(at: settingsPath) {
            var root: [String: Any] = [:]
            if let data = try? Data(contentsOf: url),
               let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                root = parsed
            }

            var hooks = root["hooks"] as? [String: Any] ?? [:]
            for (name, blocking) in events {
                var entries = hooks[name] as? [[String: Any]] ?? []
                // Drop any previous SlopIsland entry (idempotent / updates command).
                entries.removeAll { entry in
                    let inner = entry["hooks"] as? [[String: Any]] ?? []
                    return inner.contains { ($0["command"] as? String)?.contains(marker) == true }
                }
                var hook: [String: Any] = ["type": "command", "command": command]
                if blocking { hook["timeout"] = 86400 }
                entries.append(["matcher": "*", "hooks": [hook]])
                hooks[name] = entries
            }
            root["hooks"] = hooks

            let out = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted])
            let tmp = url.appendingPathExtension("slopisland-tmp")
            try out.write(to: tmp, options: .atomic)
            _ = try? FileManager.default.removeItem(at: url)
            try FileManager.default.moveItem(at: tmp, to: url)
        }
    }

    /// Removes SlopIsland's own hook entries (used when disabling).
    static func uninstall() {
        let url = URL(fileURLWithPath: settingsPath)
        try? withFileLock(at: settingsPath) {
            guard let data = try? Data(contentsOf: url),
                  var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  var hooks = root["hooks"] as? [String: Any] else { return }
            for (name, _) in events {
                guard var entries = hooks[name] as? [[String: Any]] else { continue }
                entries.removeAll { entry in
                    let inner = entry["hooks"] as? [[String: Any]] ?? []
                    return inner.contains { ($0["command"] as? String)?.contains(marker) == true }
                }
                hooks[name] = entries
            }
            root["hooks"] = hooks
            let out = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted])
            try out.write(to: url, options: .atomic)
        }
    }

    // MARK: - File lock

    private static func withFileLock(at path: String, _ body: () throws -> Void) rethrows {
        let lockPath = path + ".lock"
        let fd = open(lockPath, O_CREAT | O_RDWR, 0o600)
        if fd >= 0 {
            flock(fd, LOCK_EX)
            defer { flock(fd, LOCK_UN); close(fd) }
            try body()
        } else {
            try body() // best-effort if lock can't be created
        }
    }
}
