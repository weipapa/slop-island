import AppKit

struct TerminalFocuser {
    static let shared = TerminalFocuser()

    func focusTerminal() {
        NSLog("[SlopIsland] focusTerminal called")
        DispatchQueue.global(qos: .userInitiated).async {
            let tree = ProcessTreeBuilder.shared.buildTree()
            var terminalCommand: String?

            for (_, info) in tree {
                guard info.command.lowercased().contains("claude") else { continue }
                if let termPID = ProcessTreeBuilder.shared.findTerminalPID(forProcess: info.pid, tree: tree),
                   let termInfo = tree[termPID] {
                    terminalCommand = termInfo.command
                    NSLog("[SlopIsland] Found terminal: \(termInfo.command)")
                    break
                }
            }

            guard let command = terminalCommand else {
                NSLog("[SlopIsland] No terminal found")
                return
            }
            let appName = Self.appName(for: command)
            NSLog("[SlopIsland] appName: \(appName ?? "nil")")
            guard let name = appName else { return }

            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            task.arguments = ["-a", name]
            do {
                try task.run()
                task.waitUntilExit()
                NSLog("[SlopIsland] open -a \(name) exit code: \(task.terminationStatus)")
            } catch {
                NSLog("[SlopIsland] open failed: \(error)")
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
