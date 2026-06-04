import AppKit

struct TerminalFocuser {
    static let shared = TerminalFocuser()

    /// Focus the terminal hosting a `claude` process. Calls `completion(true)`
    /// on the main queue once `open -a` has run, or `completion(false)` if no
    /// terminal could be resolved.
    func focusTerminal(completion: ((Bool) -> Void)? = nil) {
        DispatchQueue.global(qos: .userInitiated).async {
            let tree = ProcessTreeBuilder.shared.buildTree()
            var terminalCommand: String?

            for (_, info) in tree {
                guard info.command.lowercased().contains("claude") else { continue }
                if let termPID = ProcessTreeBuilder.shared.findTerminalPID(forProcess: info.pid, tree: tree),
                   let termInfo = tree[termPID] {
                    terminalCommand = termInfo.command
                    break
                }
            }

            func finish(_ ok: Bool) {
                DispatchQueue.main.async { completion?(ok) }
            }

            guard let command = terminalCommand else {
                finish(false)
                return
            }
            let appName = Self.appName(for: command)
            guard let name = appName else { finish(false); return }

            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            task.arguments = ["-a", name]
            do {
                try task.run()
                task.waitUntilExit()
                finish(task.terminationStatus == 0)
            } catch {
                finish(false)
            }
        }
    }

    private static func appName(for command: String) -> String? {
        let lower = command.lowercased()
        let mapping: [(pattern: String, app: String)] = [
            ("ghostty", "Ghostty"),
            ("iterm", "iTerm"),
            ("terminal.app", "Terminal"),
            ("alacritty", "Alacritty"),
            ("kitty", "kitty"),
            ("wezterm", "WezTerm"),
            ("visual studio code", "Visual Studio Code"),
            ("vscode", "Visual Studio Code"),
            ("cursor", "Cursor"),
            ("zed", "Zed"),
        ]
        for entry in mapping {
            if lower.contains(entry.pattern) { return entry.app }
        }
        return nil
    }
}
