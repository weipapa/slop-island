import SwiftUI

struct SettingsContentView: View {
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var soundEnabled = AppSettings.notificationSoundEnabled
    @State private var hasAccessibility = KeySender.hasAccessibilityPermission

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            try LoginItem.setEnabled(newValue)
                        } catch {
                            // Roll the toggle back to the real state on failure.
                            NSLog("[SlopIsland] login item toggle failed: \(error)")
                            launchAtLogin = LoginItem.isEnabled
                        }
                    }

                Toggle("Notification sound", isOn: $soundEnabled)
                    .onChange(of: soundEnabled) { _, newValue in
                        AppSettings.notificationSoundEnabled = newValue
                    }
            }

            Section("Accessibility") {
                HStack {
                    Image(systemName: hasAccessibility
                        ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(hasAccessibility ? .green : .orange)
                    Text(hasAccessibility ? "Permission granted" : "Permission needed")
                    Spacer()
                    if !hasAccessibility {
                        Button("Open System Settings") { openAccessibilitySettings() }
                    }
                }
                if !hasAccessibility {
                    Text("Required to answer prompts in the terminal. Without it, answering a question silently does nothing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
        // Re-read live state whenever the window is shown again (the user may
        // have toggled login items or granted permission while it was closed).
        .onReceive(NotificationCenter.default.publisher(
            for: NSWindow.didBecomeKeyNotification)) { _ in
            launchAtLogin = LoginItem.isEnabled
            soundEnabled = AppSettings.notificationSoundEnabled
            hasAccessibility = KeySender.hasAccessibilityPermission
        }
    }

    private func openAccessibilitySettings() {
        KeySender.requestAccessibilityPermission()
        if let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
