import SwiftUI

struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        Path(roundedRect: rect, cornerRadii: .init(
            topLeading: topRadius,
            bottomLeading: bottomRadius,
            bottomTrailing: bottomRadius,
            topTrailing: topRadius
        ))
    }
}

struct IslandView: View {
    var viewModel: IslandViewModel
    private let store = SessionStore.shared

    var body: some View {
        ZStack(alignment: .top) {
            Color.black

            if viewModel.status == .opened {
                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: viewModel.geometry.notchHeight)
                    contentView
                }
            }
        }
        .clipShape(NotchShape(
            topRadius: 6,
            bottomRadius: viewModel.status == .opened ? 22 : 6
        ))
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var contentView: some View {
        VStack(spacing: 0) {
            switch viewModel.contentType {
            case .sessions, .settings, .chat:
                headerRow
                    .frame(height: 32)
            case .question, .permission:
                EmptyView()
            }

            switch viewModel.contentType {
            case .sessions:
                SessionListContentView(viewModel: viewModel)
            case .settings:
                SettingsContentView(viewModel: viewModel)
            case .chat(let sessionID):
                if let session = store.sessions[sessionID] {
                    ChatContentView(sessionID: sessionID, session: session, viewModel: viewModel)
                }
            case .question(let question):
                QuestionContentView(question: question) { index in
                    SessionStore.shared.answerQuestion(question, optionIndex: index)
                    viewModel.dismissQuestion()
                }
            case .permission(let session, let context):
                PermissionRequestView(session: session, context: context) {
                    SessionStore.shared.process(.permissionApproved(sessionID: session.sessionID))
                    viewModel.dismissPermission()
                } onDeny: {
                    SessionStore.shared.process(.permissionDenied(sessionID: session.sessionID))
                    viewModel.dismissPermission()
                }
            }
        }
        .padding(12)
    }

    private var headerRow: some View {
        HStack {
            if case .chat = viewModel.contentType {
                Button {
                    viewModel.exitChat()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
    }
}
