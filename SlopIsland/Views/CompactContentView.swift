import AppKit

final class CompactContentView: NSView {

    private let dotView = NSView()
    private let statusLabel = NSTextField(labelWithString: "")

    private var pulseTimer: Timer?

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
        dotView.layer?.backgroundColor = NSColor(red: 0.204, green: 0.831, blue: 0.600, alpha: 1).cgColor
        dotView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dotView)

        statusLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        statusLabel.textColor = NSColor(white: 0.85, alpha: 1)
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.maximumNumberOfLines = 1
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(statusLabel)

        NSLayoutConstraint.activate([
            dotView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            dotView.centerYAnchor.constraint(equalTo: centerYAnchor),
            dotView.widthAnchor.constraint(equalToConstant: 7),
            dotView.heightAnchor.constraint(equalToConstant: 7),

            statusLabel.leadingAnchor.constraint(equalTo: dotView.trailingAnchor, constant: 8),
            statusLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            statusLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        startPulse()
    }

    func configure(session: SessionState) {
        switch session.phase {
        case .processing(let action):
            statusLabel.stringValue = action
            dotView.layer?.backgroundColor = NSColor(red: 0.204, green: 0.831, blue: 0.600, alpha: 1).cgColor
        case .idle:
            statusLabel.stringValue = "idle"
            dotView.layer?.backgroundColor = NSColor(white: 0.4, alpha: 1).cgColor
        default:
            statusLabel.stringValue = session.projectName
            dotView.layer?.backgroundColor = NSColor(white: 0.4, alpha: 1).cgColor
        }
    }

    private func startPulse() {
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.9, repeats: true) { [weak self] _ in
            guard let dot = self?.dotView.layer else { return }
            let anim = CABasicAnimation(keyPath: "opacity")
            anim.fromValue = 1.0
            anim.toValue = 0.4
            anim.duration = 0.9
            anim.autoreverses = true
            dot.add(anim, forKey: "pulse")
        }
    }

    deinit {
        pulseTimer?.invalidate()
    }
}
