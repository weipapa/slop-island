import SwiftUI

struct ChatContentView: View {
    let sessionID: String
    let session: SessionState
    var viewModel: IslandViewModel

    @State private var history: [ChatHistoryItem] = []
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            chatHeader
            Divider().background(Color.white.opacity(0.08))

            if isLoading {
                Spacer()
                ProgressView()
                    .controlSize(.small)
                    .tint(.white.opacity(0.4))
                Spacer()
            } else if history.isEmpty {
                Spacer()
                Text("No messages yet")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.3))
                Spacer()
            } else {
                messageList
            }
        }
        .task {
            await ChatHistoryManager.shared.loadHistory(
                jsonlPath: session.jsonlPath,
                sessionID: sessionID
            )
            history = ChatHistoryManager.shared.history(for: sessionID)
            isLoading = false
        }
    }

    private var chatHeader: some View {
        HStack(spacing: 8) {
            Button {
                viewModel.exitChat()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)

            Text(session.displayTitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)

            Spacer()
        }
        .padding(.bottom, 8)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(history) { item in
                        messageView(for: item)
                            .id(item.id)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.vertical, 10)
            }
            .onAppear {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    @ViewBuilder
    private func messageView(for item: ChatHistoryItem) -> some View {
        switch item.type {
        case .user(let text):
            HStack {
                Spacer()
                Text(text)
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .frame(maxWidth: 350, alignment: .trailing)
            }

        case .assistant(let text):
            MarkdownTextView(text: text)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.85))
                .frame(maxWidth: 400, alignment: .leading)

        case .toolCall(let name, let input, let status):
            HStack(spacing: 6) {
                Image(systemName: "wrench")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.4))
                Text(name)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
                if !input.isEmpty {
                    Text(input)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.3))
                        .lineLimit(1)
                }
            }

        case .thinking(let text):
            DisclosureGroup {
                Text(text)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.3))
            } label: {
                Text("thinking...")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.3))
            }
            .tint(.white.opacity(0.3))
        }
    }
}
