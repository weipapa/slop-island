import SwiftUI

struct SessionRowContentView: View {
    let session: SessionState
    let terminalName: String
    let onTap: () -> Void
    let onApprove: () -> Void
    let onDeny: () -> Void

    @State private var isHovered = false

    private let claudeOrange = Color(red: 0.85, green: 0.47, blue: 0.34)
    private let amber = Color(red: 1.0, green: 0.7, blue: 0.0)
    private let green = Color(red: 0.4, green: 0.75, blue: 0.45)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                stateIndicator
                    .frame(width: 16, height: 16)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(session.displayTitle)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)

                        Spacer(minLength: 4)

                        HStack(spacing: 4) {
                            tagView("Claude")
                            tagView(terminalName)
                            Text(elapsedTime)
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.3))
                        }
                    }

                    subtitleView
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            if case .waitingForApproval = session.phase {
                HStack(spacing: 8) {
                    Spacer()
                    Button { onDeny() } label: {
                        Text("Deny")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Button { onApprove() } label: {
                        Text("Allow")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.black)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.9))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isHovered ? Color.white.opacity(0.06) : Color.clear)
        )
        .onHover { isHovered = $0 }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }

    private func tagView(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(.white.opacity(0.5))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    @ViewBuilder
    private var stateIndicator: some View {
        switch session.phase {
        case .processing:
            ProcessingSpinner(color: claudeOrange)
        case .waitingForApproval, .waitingForQuestion:
            ProcessingSpinner(color: amber)
        case .ended:
            Circle().fill(green).frame(width: 7, height: 7)
        case .idle:
            Circle().fill(Color.white.opacity(0.2)).frame(width: 7, height: 7)
        }
    }

    @ViewBuilder
    private var subtitleView: some View {
        switch session.phase {
        case .processing(let action):
            Text(action)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(red: 0.4, green: 0.6, blue: 1.0))
                .lineLimit(1)

        case .waitingForApproval(let ctx):
            VStack(alignment: .leading, spacing: 2) {
                Text("\(ctx.toolName) \(ctx.toolInput)")
                    .font(.system(size: 11))
                    .foregroundColor(amber.opacity(0.7))
                    .lineLimit(1)
                Text("Waiting for approval")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(amber.opacity(0.9))
            }

        case .waitingForQuestion(let q):
            VStack(alignment: .leading, spacing: 2) {
                Text(q.items.first?.prompt ?? "")
                    .font(.system(size: 11))
                    .foregroundColor(Color(red: 0.0, green: 0.75, blue: 0.85).opacity(0.7))
                    .lineLimit(1)
                Text(questionSubtitle(q))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(red: 0.0, green: 0.75, blue: 0.85))
            }

        case .ended:
            Text("Done \u{2014} click to jump")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(green)

        case .idle:
            Text("Idle")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.3))
        }
    }

    private func questionSubtitle(_ q: UserQuestion) -> String {
        let count = q.items.count
        if count > 1 {
            return "Claude asks \(count) questions \u{2014} click to answer"
        }
        return "Claude asks \u{2014} click to answer"
    }

    private var elapsedTime: String {
        let seconds = Int(Date().timeIntervalSince(session.lastActivity))
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        return "\(seconds / 3600)h"
    }
}
