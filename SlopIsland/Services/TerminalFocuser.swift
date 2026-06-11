import AppKit

struct TerminalFocuser {
    static let shared = TerminalFocuser()

    private static let ghosttyBundleID = "com.mitchellh.ghostty"
    /// Ghostty updates window/tab focus asynchronously after each AppleScript
    /// command; small settle delays let it catch up before we move on.
    private static let ghosttyWindowActivationDelay = 0.04
    private static let ghosttyFocusSettleDelay = 0.08

    /// Focus the terminal hosting a `claude` process, without knowing which tab.
    /// Kept for callers that have no session context.
    func focusTerminal(completion: ((Bool) -> Void)? = nil) {
        focusTerminal(cwd: "", completion: completion)
    }

    /// Focus the specific terminal tab whose working directory matches `cwd`.
    /// Falls back to plain app activation (`open -a`) when `cwd` is empty,
    /// Ghostty isn't running, or no tab matches — so behavior never regresses
    /// for non-Ghostty terminals or unmapped sessions.
    func focusTerminal(cwd: String, completion: ((Bool) -> Void)? = nil) {
        DispatchQueue.global(qos: .userInitiated).async {
            func finish(_ ok: Bool) {
                DispatchQueue.main.async { completion?(ok) }
            }

            // Precise path: Ghostty + a known cwd. Select the matching tab.
            if !cwd.isEmpty, Self.isGhosttyRunning(),
               Self.focusGhosttyTab(workingDirectory: cwd) {
                finish(true)
                return
            }

            // Fallback: resolve the terminal app hosting a `claude` process and
            // just activate it.
            Self.activateClaudeHostTerminal(finish: finish)
        }
    }

    // MARK: - Ghostty precise focus

    private static func isGhosttyRunning() -> Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: ghosttyBundleID).isEmpty == false
    }

    /// Walk Ghostty's windows/tabs/terminals via AppleScript, find the first
    /// terminal whose `working directory` matches `workingDirectory`, then
    /// activate its window, select its tab, and focus it. Returns true only when
    /// a tab actually matched and was focused.
    private static func focusGhosttyTab(workingDirectory: String) -> Bool {
        let target = escapeAppleScript(workingDirectory)
        let script = """
        tell application "Ghostty"
            if not (it is running) then return ""
            activate

            set targetWindow to missing value
            set targetTab to missing value
            set targetTerminal to missing value

            repeat with aWindow in windows
                repeat with aTab in tabs of aWindow
                    repeat with aTerminal in terminals of aTab
                        if (working directory of aTerminal as text) is "\(target)" then
                            set targetWindow to aWindow
                            set targetTab to aTab
                            set targetTerminal to aTerminal
                            exit repeat
                        end if
                    end repeat
                    if targetTerminal is not missing value then exit repeat
                end repeat
                if targetTerminal is not missing value then exit repeat
            end repeat

            if targetTerminal is missing value then return ""

            if targetWindow is not missing value then
                activate window targetWindow
                delay \(ghosttyWindowActivationDelay)
            end if
            if targetTab is not missing value then
                select tab targetTab
                delay \(ghosttyWindowActivationDelay)
            end if
            focus targetTerminal
            delay \(ghosttyFocusSettleDelay)
            return "matched"
        end tell
        return ""
        """
        return runAppleScript(script) == "matched"
    }

    @discardableResult
    private static func runAppleScript(_ script: String) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return nil
        }
        guard task.terminationStatus == 0 else { return nil }
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func escapeAppleScript(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    // MARK: - Fallback app activation

    private static func activateClaudeHostTerminal(finish: (Bool) -> Void) {
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

        guard let command = terminalCommand, let name = appName(for: command) else {
            finish(false)
            return
        }

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
