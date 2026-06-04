import SwiftUI

struct QuestionContentView: View {
    let question: UserQuestion
    let onDismiss: () -> Void

    private let cyan = Color(red: 0.0, green: 0.75, blue: 0.85)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "bubble.left.fill")
                    .font(.system(size: 11))
                    .foregroundColor(cyan)
                Text("Claude asks")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(cyan)
            }

            Text(question.question)
                .font(.system(size: 13))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 6) {
                ForEach(Array(question.options.enumerated()), id: \.offset) { index, option in
                    Button {
                        KeySender.sendToTerminal(text: "\(index + 1)")
                        onDismiss()
                    } label: {
                        HStack(spacing: 8) {
                            Text("\u{2318}\(index + 1)")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(.white.opacity(0.5))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.white.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 4))

                            Text(option.label)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white)

                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(4)
    }
}
