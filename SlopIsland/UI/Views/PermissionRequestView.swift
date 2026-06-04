import SwiftUI

struct PermissionRequestView: View {
    let session: SessionState
    let context: PermissionContext
    let onAllow: () -> Void
    let onDeny: () -> Void

    private let amber = Color(red: 1.0, green: 0.6, blue: 0.2)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 6) {
                Circle()
                    .fill(amber)
                    .frame(width: 8, height: 8)
                Text("Permission Request")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(amber)
            }

            // Tool name + file
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 12))
                    .foregroundColor(amber)
                Text(context.toolName)
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                Text(displayInput)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)
            }

            // Tool input detail
            if !context.toolInput.isEmpty {
                Text(context.toolInput)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(5)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // Buttons
            HStack(spacing: 10) {
                Button { onDeny() } label: {
                    HStack(spacing: 4) {
                        Text("Deny")
                        Text("\u{2318}N")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)

                Button { onAllow() } label: {
                    HStack(spacing: 4) {
                        Text("Allow")
                        Text("\u{2318}Y")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.black.opacity(0.4))
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.9))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(0)
    }

    private var displayInput: String {
        switch context.toolName {
        case "Edit", "Write", "Read":
            return (context.toolInput as NSString).lastPathComponent
        default:
            return ""
        }
    }
}
