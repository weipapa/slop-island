import AppKit
import SwiftUI

class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    /// The window is always at full opened size but mostly transparent. Only
    /// the live content rect should swallow clicks; everything else passes
    /// through to the apps underneath.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let panel = window as? NotchPanel else { return super.hitTest(point) }
        // TEMP DIAGNOSTIC: always pass through. If Ghostty becomes clickable,
        // the culprit is this hitTest's contains() check; if not, it's window
        // level / event routing.
        _ = panel
        return nil
    }
}

class NotchViewController: NSViewController {
    let viewModel: IslandViewModel

    init(viewModel: IslandViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let hosting = FirstClickHostingView(rootView: IslandView(viewModel: viewModel))
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.translatesAutoresizingMaskIntoConstraints = true
        hosting.autoresizingMask = [.width, .height]
        self.view = hosting
    }
}
