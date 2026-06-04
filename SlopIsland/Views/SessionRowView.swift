import AppKit

final class SessionRowView: NSView {

    private let indicatorLabel = NSTextField(labelWithString: "")
    private let projectLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let actionContainer = NSView()
    private let allowButton = NSButton(frame: .zero)
    private let denyButton = NSButton(frame: .zero)
    private let statusLabel = NSTextField(labelWithString: "")

    private var spinnerTimer: Timer?
    private var spinnerIndex = 0
    private let spinnerChars = ["\u{00B7}", "\u{2722}", "\u{2733}", "\u{2217}", "\u{273B}", "\u{273D}"]
    private var trackingArea: NSTrackingArea?

    private(set) var sessionID: String = ""
    var onAllow: (() -> Void)?
    var onDeny: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true

        indicatorLabel.font = .systemFont(ofSize: 14, weight: .bold)
        indicatorLabel.alignment = .center
        indicatorLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(indicatorLabel)

        projectLabel.font = .systemFont(ofSize: 13, weight: .medium)
        projectLabel.textColor = NSColor(white: 1, alpha: 0.9)
        projectLabel.lineBreakMode = .byTruncatingTail
        projectLabel.maximumNumberOfLines = 1
        projectLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(projectLabel)

        subtitleLabel.font = .systemFont(ofSize: 11, weight: .regular)
        subtitleLabel.textColor = NSColor(white: 1, alpha: 0.5)
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.maximumNumberOfLines = 1
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(subtitleLabel)

        actionContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(actionContainer)

        let denyColor = NSColor(white: 1, alpha: 0.6)
        styleCapsule(denyButton, title: "Deny", bgAlpha: 0.1, textColor: denyColor)
        denyButton.target = self
        denyButton.action = #selector(denyTapped)
        actionContainer.addSubview(denyButton)

        styleCapsule(allowButton, title: "Allow", bgAlpha: 0.9, textColor: .black)
        allowButton.target = self
        allowButton.action = #selector(allowTapped)
        actionContainer.addSubview(allowButton)

        statusLabel.font = .systemFont(ofSize: 10, weight: .regular)
        statusLabel.textColor = NSColor(white: 1, alpha: 0.35)
        statusLabel.alignment = .right
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        actionContainer.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            indicatorLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            indicatorLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            indicatorLabel.widthAnchor.constraint(equalToConstant: 16),

            projectLabel.leadingAnchor.constraint(equalTo: indicatorLabel.trailingAnchor, constant: 8),
            projectLabel.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            projectLabel.trailingAnchor.constraint(lessThanOrEqualTo: actionContainer.leadingAnchor, constant: -6),

            subtitleLabel.leadingAnchor.constraint(equalTo: projectLabel.leadingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: projectLabel.bottomAnchor, constant: 1),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: actionContainer.leadingAnchor, constant: -6),

            actionContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            actionContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
            actionContainer.widthAnchor.constraint(equalToConstant: 120),
            actionContainer.heightAnchor.constraint(equalToConstant: 24),
        ])

        denyButton.translatesAutoresizingMaskIntoConstraints = false
        allowButton.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            allowButton.trailingAnchor.constraint(equalTo: actionContainer.trailingAnchor),
            allowButton.centerYAnchor.constraint(equalTo: actionContainer.centerYAnchor),
            allowButton.heightAnchor.constraint(equalToConstant: 22),
            allowButton.widthAnchor.constraint(equalToConstant: 52),

            denyButton.trailingAnchor.constraint(equalTo: allowButton.leadingAnchor, constant: -6),
            denyButton.centerYAnchor.constraint(equalTo: actionContainer.centerYAnchor),
            denyButton.heightAnchor.constraint(equalToConstant: 22),
            denyButton.widthAnchor.constraint(equalToConstant: 45),

            statusLabel.trailingAnchor.constraint(equalTo: actionContainer.trailingAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: actionContainer.centerYAnchor),
            statusLabel.widthAnchor.constraint(equalTo: actionContainer.widthAnchor),
        ])
    }

    private func styleCapsule(_ button: NSButton, title: String, bgAlpha: CGFloat, textColor: NSColor) {
        button.title = title
        button.bezelStyle = .inline
        button.isBordered = false
        button.font = .systemFont(ofSize: 10, weight: .medium)
        button.contentTintColor = textColor
        button.wantsLayer = true
        button.layer?.cornerRadius = 11
        button.layer?.backgroundColor = NSColor(white: 1, alpha: bgAlpha).cgColor
    }

    func configure(session: SessionState) {
        sessionID = session.sessionID
        projectLabel.stringValue = session.projectName

        spinnerTimer?.invalidate()
        spinnerTimer = nil

        switch session.phase {
        case .processing(let action):
            indicatorLabel.textColor = NSColor(red: 0.85, green: 0.47, blue: 0.34, alpha: 1)
            subtitleLabel.stringValue = action
            showButtons(false)
            statusLabel.stringValue = ""
            startSpinner()

        case .waitingForApproval(let ctx):
            indicatorLabel.textColor = NSColor(red: 1.0, green: 0.7, blue: 0.0, alpha: 1)
            subtitleLabel.stringValue = "\(ctx.toolName) \(ctx.toolInput)"
            subtitleLabel.textColor = NSColor(red: 1.0, green: 0.7, blue: 0.0, alpha: 0.7)
            showButtons(true)
            startSpinner()

        case .ended:
            indicatorLabel.textColor = NSColor(red: 0.4, green: 0.75, blue: 0.45, alpha: 1)
            indicatorLabel.stringValue = "\u{25CF}"
            subtitleLabel.stringValue = "Done"
            subtitleLabel.textColor = NSColor(white: 1, alpha: 0.5)
            showButtons(false)
            statusLabel.stringValue = ""

        case .idle:
            indicatorLabel.textColor = NSColor(white: 1, alpha: 0.2)
            indicatorLabel.stringValue = "\u{25CF}"
            subtitleLabel.stringValue = "Idle"
            subtitleLabel.textColor = NSColor(white: 1, alpha: 0.5)
            showButtons(false)
            statusLabel.stringValue = ""
        }
    }

    private func showButtons(_ show: Bool) {
        allowButton.isHidden = !show
        denyButton.isHidden = !show
        statusLabel.isHidden = show

        if show {
            allowButton.alphaValue = 0
            denyButton.alphaValue = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.2
                    self.denyButton.animator().alphaValue = 1
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.2
                    self.allowButton.animator().alphaValue = 1
                }
            }
        }
    }

    private func startSpinner() {
        spinnerIndex = 0
        indicatorLabel.stringValue = spinnerChars[0]
        spinnerTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.spinnerIndex = (self.spinnerIndex + 1) % self.spinnerChars.count
            self.indicatorLabel.stringValue = self.spinnerChars[self.spinnerIndex]
        }
    }

    // MARK: - Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        let ta = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(ta)
        trackingArea = ta
    }

    override func mouseEntered(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            self.animator().layer?.backgroundColor = NSColor(white: 1, alpha: 0.06).cgColor
        }
    }

    override func mouseExited(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            self.animator().layer?.backgroundColor = NSColor.clear.cgColor
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    @objc private func allowTapped() { onAllow?() }
    @objc private func denyTapped() { onDeny?() }

    deinit {
        spinnerTimer?.invalidate()
    }
}
