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
        // The hosting window is a fixed, full-opened-size, mostly-transparent
        // panel. We draw only the live island here, top-anchored under the
        // notch, and let SwiftUI animate its size between closed and opened —
        // the window itself never resizes.
        let size = viewModel.status == .opened
            ? viewModel.openedSize
            : CGSize(width: viewModel.geometry.notchWidth,
                     height: viewModel.geometry.notchHeight)

        return VStack(spacing: 0) {
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
            .frame(width: size.width, height: size.height)
            .clipShape(NotchShape(
                topRadius: 6,
                bottomRadius: viewModel.status == .opened ? 22 : 6
            ))

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: viewModel.status)
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: viewModel.openedSize.height)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var contentView: some View {
        switch viewModel.contentType {
        case .sessions:
            VStack(spacing: 8) {
                headerRow
                SessionListContentView(viewModel: viewModel)
            }
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

    /// Top-right controls inside the opened panel. This is the only entry point
    /// to Settings and Quit (the app has no menu-bar item), so it must stay
    /// reachable: the sessions view shows it even when the list is empty.
    private var headerRow: some View {
        HStack(spacing: 6) {
            Spacer()
            headerButton(systemName: "gearshape.fill") {
                SettingsWindowController.shared.show()
            }
            headerButton(systemName: "power") {
                NSApp.terminate(nil)
            }
        }
    }

    private func headerButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.55))
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(0.08))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}
