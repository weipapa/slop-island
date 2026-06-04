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
        switch viewModel.contentType {
        case .sessions:
            VStack(spacing: 0) { SessionListContentView(viewModel: viewModel) }
                .padding(10)
        case .chat(let sessionID):
            if let session = store.sessions[sessionID] {
                VStack(spacing: 0) {
                    ChatContentView(sessionID: sessionID, session: session, viewModel: viewModel)
                }
                .padding(10)
            }
        case .question(let question):
            // Top-aligned scroll view: panel height is a fixed estimate, the
            // scroll view absorbs any shortfall so content is never clipped and
            // always starts at the first question.
            ScrollView(.vertical, showsIndicators: false) {
                QuestionContentView(question: question, onComplete: { indices in
                    SessionStore.shared.answerQuestion(question, optionIndices: indices)
                    viewModel.dismissQuestion()
                }, onPageChange: { page in
                    viewModel.setQuestionPage(page)
                })
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        case .permission(let session, let context):
            VStack(spacing: 0) {
                PermissionRequestView(session: session, context: context) {
                    SessionStore.shared.process(.permissionApproved(sessionID: session.sessionID))
                    viewModel.dismissPermission()
                } onDeny: {
                    SessionStore.shared.process(.permissionDenied(sessionID: session.sessionID))
                    viewModel.dismissPermission()
                }
            }
            .padding(10)
        }
    }
}
