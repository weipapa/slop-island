import AppKit

final class DoneContentView: NSView {

    private let dotView = NSView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let badgeLabel = NSTextField(labelWithString: "")
    private let badgeContainer = NSView()

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

        dotView.wantsLayer = true
        dotView.layer?.cornerRadius = 3.5
        dotView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dotView)

        nameLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        nameLabel.textColor = NSColor(white: 0.94, alpha: 1)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nameLabel)

        badgeContainer.wantsLayer = true
        badgeContainer.layer?.cornerRadius = 4
        badgeContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(badgeContainer)

        badgeLabel.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .semibold)
        badgeLabel.alignment = .center
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        badgeContainer.addSubview(badgeLabel)

        NSLayoutConstraint.activate([
            dotView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            dotView.centerYAnchor.constraint(equalTo: centerYAnchor),
            dotView.widthAnchor.constraint(equalToConstant: 7),
            dotView.heightAnchor.constraint(equalToConstant: 7),

            nameLabel.leadingAnchor.constraint(equalTo: dotView.trailingAnchor, constant: 8),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            badgeContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            badgeContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
            badgeContainer.heightAnchor.constraint(equalToConstant: 20),

            badgeLabel.leadingAnchor.constraint(equalTo: badgeContainer.leadingAnchor, constant: 6),
            badgeLabel.trailingAnchor.constraint(equalTo: badgeContainer.trailingAnchor, constant: -6),
            badgeLabel.centerYAnchor.constraint(equalTo: badgeContainer.centerYAnchor),
        ])
    }

    func configure(session: SessionState) {
        nameLabel.stringValue = session.projectName

        let green = NSColor(red: 0.204, green: 0.831, blue: 0.600, alpha: 1)
        dotView.layer?.backgroundColor = green.cgColor
        badgeLabel.stringValue = "DONE \u{2713}"
        badgeLabel.textColor = green
        badgeContainer.layer?.backgroundColor = green.withAlphaComponent(0.12).cgColor
        badgeContainer.layer?.borderColor = green.withAlphaComponent(0.2).cgColor
        badgeContainer.layer?.borderWidth = 1
    }
}
