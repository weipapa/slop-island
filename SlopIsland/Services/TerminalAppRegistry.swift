import Foundation

struct TerminalAppRegistry {
    static let bundleMapping: [(patterns: [String], bundleID: String)] = [
        (["terminal.app", "/terminal"], "com.apple.Terminal"),
        (["iterm"], "com.googlecode.iterm2"),
        (["ghostty"], "com.mitchellh.ghostty"),
        (["alacritty"], "org.alacritty"),
        (["kitty.app"], "net.kovidgoyal.kitty"),
        (["wezterm"], "com.github.wez.wezterm"),
        (["code-insiders"], "com.microsoft.VSCodeInsiders"),
        (["visual studio code", "vscode"], "com.microsoft.VSCode"),
        (["cursor.app"], "com.todesktop.230313mzl4w4u92"),
        (["zed.app"], "dev.zed.Zed"),
    ]

    static func isTerminal(_ command: String) -> Bool {
        let lower = command.lowercased()
        return bundleMapping.contains { entry in
            entry.patterns.contains { lower.contains($0) }
        }
    }
}
