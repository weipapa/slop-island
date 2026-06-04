import AppKit

final class SessionListView: NSView {

    private let scrollView = NSScrollView()
    private let stackView = NSStackView()
    private var rowViews: [String: SessionRowView] = [:]

    var onAllow: ((String) -> Void)?
    var onDeny: ((String) -> Void)?

    override var isFlipped: Bool { true }

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

        let docView = FlippedView()
        docView.translatesAutoresizingMaskIntoConstraints = false

        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 2
        stackView.translatesAutoresizingMaskIntoConstraints = false
        docView.addSubview(stackView)

        scrollView.documentView = docView
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .overlay
        scrollView.scrollerKnobStyle = .light
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            stackView.topAnchor.constraint(equalTo: docView.topAnchor, constant: 4),
            stackView.leadingAnchor.constraint(equalTo: docView.leadingAnchor, constant: 4),
            stackView.trailingAnchor.constraint(equalTo: docView.trailingAnchor, constant: -4),
            stackView.bottomAnchor.constraint(equalTo: docView.bottomAnchor, constant: -4),

            docView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
        ])
    }

    func configure(sessions: [SessionState]) {
        let sorted = sessions.sorted { priority($0.phase) < priority($1.phase) }

        let currentIDs = Set(rowViews.keys)
        let newIDs = Set(sorted.map { $0.sessionID })

        for id in currentIDs.subtracting(newIDs) {
            if let row = rowViews.removeValue(forKey: id) {
                row.removeFromSuperview()
            }
        }

        let existingArranged = stackView.arrangedSubviews
        for v in existingArranged {
            stackView.removeArrangedSubview(v)
        }

        for session in sorted {
            let row: SessionRowView
            if let existing = rowViews[session.sessionID] {
                row = existing
            } else {
                row = SessionRowView(frame: NSRect(x: 0, y: 0, width: bounds.width - 8, height: 42))
                rowViews[session.sessionID] = row
            }

            row.configure(session: session)
            row.onAllow = { [weak self] in self?.onAllow?(session.sessionID) }
            row.onDeny = { [weak self] in self?.onDeny?(session.sessionID) }

            row.translatesAutoresizingMaskIntoConstraints = false
            stackView.addArrangedSubview(row)

            NSLayoutConstraint.activate([
                row.heightAnchor.constraint(equalToConstant: 42),
                row.leadingAnchor.constraint(equalTo: stackView.leadingAnchor),
                row.trailingAnchor.constraint(equalTo: stackView.trailingAnchor),
            ])
        }
    }

    private func priority(_ phase: SessionPhase) -> Int {
        switch phase {
        case .waitingForApproval: return 0
        case .processing: return 1
        case .ended: return 2
        case .idle: return 3
        }
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
