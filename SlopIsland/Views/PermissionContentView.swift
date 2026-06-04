import AppKit

final class PermissionContentView: NSView {

    private let dotView = NSView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let commandContainer = NSView()
    private let commandLabel = NSTextField(labelWithString: "")
    private let denyButton = NSButton(frame: .zero)
    private let allowButton = NSButton(frame: .zero)

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

    override func resetCursorRects() {
        addCursorRect(denyButton.frame, cursor: .pointingHand)
        addCursorRect(allowButton.frame, cursor: .pointingHand)
    }

    private func setupViews() {
        wantsLayer = true

        dotView.wantsLayer = true
        dotView.layer?.cornerRadius = 3
        dotView.layer?.backgroundColor = NSColor(red: 1.0, green: 0.6, blue: 0.2, alpha: 1).cgColor
        dotView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dotView)

        titleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = NSColor(white: 0.92, alpha: 1)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        subtitleLabel.font = .systemFont(ofSize: 9.5, weight: .regular)
        subtitleLabel.textColor = NSColor(white: 0.45, alpha: 1)
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(subtitleLabel)

        commandContainer.wantsLayer = true
        commandContainer.layer?.backgroundColor = NSColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 0.9).cgColor
        commandContainer.layer?.cornerRadius = 6
        commandContainer.layer?.borderColor = NSColor(white: 0.25, alpha: 1).cgColor
        commandContainer.layer?.borderWidth = 0.5
        commandContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(commandContainer)

        commandLabel.font = NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular)
        commandLabel.textColor = NSColor(red: 1.0, green: 0.85, blue: 0.5, alpha: 1)
        commandLabel.maximumNumberOfLines = 2
        commandLabel.lineBreakMode = .byTruncatingTail
        commandLabel.translatesAutoresizingMaskIntoConstraints = false
        commandContainer.addSubview(commandLabel)

        let denyColor = NSColor(red: 1.0, green: 0.42, blue: 0.42, alpha: 1)
        styleButton(denyButton, title: "\u{62D2}\u{7EDD}", color: denyColor)
        denyButton.target = self
        denyButton.action = #selector(denyTapped)
        addSubview(denyButton)

        let allowColor = NSColor(red: 0.25, green: 0.82, blue: 0.55, alpha: 1)
        styleButton(allowButton, title: "\u{6279}\u{51C6}", color: allowColor)
        allowButton.target = self
        allowButton.action = #selector(allowTapped)
        addSubview(allowButton)

        NSLayoutConstraint.activate([
            dotView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            dotView.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            dotView.widthAnchor.constraint(equalToConstant: 6),
            dotView.heightAnchor.constraint(equalToConstant: 6),

            titleLabel.leadingAnchor.constraint(equalTo: dotView.trailingAnchor, constant: 6),
            titleLabel.centerYAnchor.constraint(equalTo: dotView.centerYAnchor),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),

            commandContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            commandContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            commandContainer.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 8),
            commandContainer.heightAnchor.constraint(equalToConstant: 32),

            commandLabel.leadingAnchor.constraint(equalTo: commandContainer.leadingAnchor, constant: 8),
            commandLabel.trailingAnchor.constraint(equalTo: commandContainer.trailingAnchor, constant: -8),
            commandLabel.centerYAnchor.constraint(equalTo: commandContainer.centerYAnchor),

            allowButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            allowButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            allowButton.heightAnchor.constraint(equalToConstant: 22),
            allowButton.widthAnchor.constraint(equalToConstant: 50),

            denyButton.trailingAnchor.constraint(equalTo: allowButton.leadingAnchor, constant: -6),
            denyButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            denyButton.heightAnchor.constraint(equalToConstant: 22),
            denyButton.widthAnchor.constraint(equalToConstant: 50),
        ])
    }

    private func styleButton(_ button: NSButton, title: String, color: NSColor) {
        button.title = title
        button.bezelStyle = .inline
        button.isBordered = false
        button.font = .systemFont(ofSize: 10, weight: .medium)
        button.contentTintColor = color
        button.wantsLayer = true
        button.layer?.cornerRadius = 6
        button.layer?.backgroundColor = color.withAlphaComponent(0.1).cgColor
        button.layer?.borderColor = color.withAlphaComponent(0.2).cgColor
        button.layer?.borderWidth = 0.5
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    func configure(session: SessionState, context: PermissionContext) {
        titleLabel.stringValue = "\u{9700}\u{8981}\u{6743}\u{9650}\u{786E}\u{8BA4}"
        subtitleLabel.stringValue = "\(session.projectName) \u{00B7} \(context.toolName)"
        commandLabel.stringValue = context.toolInput
    }

    @objc private func allowTapped() { onAllow?() }
    @objc private func denyTapped() { onDeny?() }
}
