import SwiftUI
import ServiceManagement

struct SettingsContentView: View {
    var viewModel: IslandViewModel
    @State private var soundEnabled = AppSettings.notificationSoundEnabled
    @State private var launchAtLogin = false

    var body: some View {
        VStack(spacing: 2) {
            menuRow(icon: "chevron.left", label: "Back") {
                viewModel.toggleSettings()
            }

            Divider().background(Color.white.opacity(0.08)).padding(.vertical, 4)

            toggleRow(icon: "speaker.wave.2", label: "Sound", isOn: soundEnabled) {
                soundEnabled.toggle()
                AppSettings.notificationSoundEnabled = soundEnabled
            }

            toggleRow(icon: "power", label: "Launch at Login", isOn: launchAtLogin) {
                toggleLogin()
            }

            Divider().background(Color.white.opacity(0.08)).padding(.vertical, 4)

            menuRow(icon: "xmark.circle", label: "Quit", destructive: true) {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(8)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func menuRow(icon: String, label: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .frame(width: 16)
                    .foregroundColor(destructive ? .red.opacity(0.8) : .white.opacity(0.5))
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(destructive ? .red.opacity(0.8) : .white)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.clear))
        }
        .buttonStyle(.plain)
    }

    private func toggleRow(icon: String, label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .frame(width: 16)
                    .foregroundColor(.white.opacity(0.5))
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                Spacer()
                HStack(spacing: 4) {
                    Circle()
                        .fill(isOn ? Color.green : Color.white.opacity(0.2))
                        .frame(width: 6, height: 6)
                    Text(isOn ? "On" : "Off")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    private func toggleLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
            launchAtLogin.toggle()
        } catch {}
    }
}
