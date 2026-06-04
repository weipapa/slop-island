import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {

    private var panel: NotchPanel!
    private var viewController: NotchViewController!
    private var viewModel: IslandViewModel!
    private var monitor: AgentMonitor!
    private var hookServer: HookServer!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let geometry = NotchGeometry.detect()

        viewModel = IslandViewModel(geometry: geometry)
        panel = NotchPanel(geometry: geometry)
        viewModel.panel = panel
        viewController = NotchViewController(viewModel: viewModel)

        let hostingView = viewController.view
        hostingView.frame = panel.contentView!.bounds
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView!.addSubview(hostingView)
        panel.orderFrontRegardless()

        monitor = AgentMonitor()
        monitor.start()

        hookServer = HookServer()
        SessionStore.shared.hookServer = hookServer
        hookServer.start()

        HookInstaller.installIfNeeded()

        setupStoreObserver()
    }

    private func setupStoreObserver() {
        SessionStore.shared.observe { [weak self] changedSessionID, sessions in
            guard let self = self, let vm = self.viewModel else { return }

            guard let session = sessions.first(where: { $0.sessionID == changedSessionID }) else { return }

            switch session.phase {
            case .waitingForApproval(let ctx):
                vm.showPermission(session: session, context: ctx)
                NSApp.activate(ignoringOtherApps: true)
                self.panel.makeKeyAndOrderFront(nil)

            case .waitingForQuestion(let question):
                vm.showQuestion(question)
                NSApp.activate(ignoringOtherApps: true)
                self.panel.makeKeyAndOrderFront(nil)

            case .ended:
                if AppSettings.notificationSoundEnabled {
                    NSSound(named: .init("Tink"))?.play()
                }
                vm.notchOpen()
                self.panel.makeKeyAndOrderFront(nil)

            default:
                break
            }
        }
    }
}
