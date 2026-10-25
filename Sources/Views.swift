import AppKit

final class DropHintView: NSView {
    var onDrop: (([URL]) -> Void)?
    var onClick: (() -> Void)?
    var canAccept: (() -> Bool)?

    private var highlighted = false {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])

        let config = NSImage.SymbolConfiguration(pointSize: 46, weight: .light)
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "arrow.down.doc", accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        icon.contentTintColor = .tertiaryLabelColor

        let title = NSTextField(labelWithString: L("drop.title"))
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        title.textColor = .secondaryLabelColor

        let subtitle = NSTextField(labelWithString: L("drop.subtitle"))
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .tertiaryLabelColor

        let stack = NSStackView(views: [icon, title, subtitle])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.setCustomSpacing(14, after: icon)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 24, dy: 24)
        guard rect.width > 0, rect.height > 0 else { return }
        let path = NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14)
        if highlighted {
            NSColor.controlAccentColor.withAlphaComponent(0.07).setFill()
            path.fill()
        }
        path.lineWidth = 2
        let dash: [CGFloat] = [8, 6]
        path.setLineDash(dash, count: dash.count, phase: 0)
        (highlighted ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.stroke()
    }

    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) {
            onClick?()
        }
    }

    private func fileURLs(_ info: NSDraggingInfo) -> [URL] {
        info.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                            options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard canAccept?() ?? true, !fileURLs(sender).isEmpty else { return [] }
        highlighted = true
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        highlighted = false
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        highlighted = false
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        highlighted = false
        let urls = fileURLs(sender)
        guard !urls.isEmpty else { return false }
        onDrop?(urls)
        return true
    }
}

final class ProgressSheetController: NSWindowController {
    var onCancel: (() -> Void)?
    var onClose: (() -> Void)?
    private(set) var wasCancelled = false

    private var total = 0
    private var finished = 0
    private var startDate = Date()
    private var timer: Timer?
    private var isDone = false

    private let titleLabel = NSTextField(labelWithString: "")
    private let bar = NSProgressIndicator()
    private let countLabel = NSTextField(labelWithString: "")
    private let timeLabel = NSTextField(labelWithString: "")
    private let lastLabel = NSTextField(labelWithString: "")
    private let disclosure = NSButton()
    private let detailsButton = NSButton(title: L("progress.details"), target: nil, action: nil)
    private let logScroll = NSTextView.scrollableTextView()
    private var logView: NSTextView { logScroll.documentView as! NSTextView }
    private let actionButton = NSButton(title: L("button.stop"), target: nil, action: nil)

    convenience init(total: Int, title: String) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 180),
                              styleMask: [.titled], backing: .buffered, defer: false)
        self.init(window: window)
        self.total = total
        titleLabel.stringValue = title
        build()
    }

    private func build() {
        guard let content = window?.contentView else { return }

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail

        bar.style = .bar
        bar.isIndeterminate = true
        bar.minValue = 0
        bar.maxValue = Double(max(total, 1))

        for label in [countLabel, timeLabel] {
            label.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
            label.textColor = .secondaryLabelColor
        }
        countLabel.stringValue = L("progress.preparing")

        lastLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        lastLabel.textColor = .secondaryLabelColor
        lastLabel.lineBreakMode = .byTruncatingMiddle
        lastLabel.stringValue = " "

        disclosure.bezelStyle = .disclosure
        disclosure.setButtonType(.pushOnPushOff)
        disclosure.title = ""
        disclosure.target = self
        disclosure.action = #selector(toggleDetails(_:))

        detailsButton.isBordered = false
        detailsButton.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        detailsButton.target = self
        detailsButton.action = #selector(toggleDetailsFromLabel(_:))

        logView.isEditable = false
        logView.isRichText = false
        logView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        logView.textContainerInset = NSSize(width: 4, height: 4)
        logScroll.hasVerticalScroller = true
        logScroll.borderType = .bezelBorder
        logScroll.isHidden = true
        logScroll.heightAnchor.constraint(equalToConstant: 170).isActive = true

        actionButton.bezelStyle = .rounded
        actionButton.keyEquivalent = "\u{1b}"
        actionButton.target = self
        actionButton.action = #selector(actionPressed(_:))

        let counts = NSStackView(views: [countLabel, NSView(), timeLabel])
        counts.orientation = .horizontal
        let detailsRow = NSStackView(views: [disclosure, detailsButton])
        detailsRow.orientation = .horizontal
        detailsRow.spacing = 2
        let buttons = NSStackView(views: [NSView(), actionButton])
        buttons.orientation = .horizontal

        let stack = NSStackView(views: [titleLabel, bar, counts, lastLabel, detailsRow, logScroll, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.setCustomSpacing(4, after: bar)
        stack.setCustomSpacing(12, after: lastLabel)
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 16, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        var constraints: [NSLayoutConstraint] = [
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            content.widthAnchor.constraint(equalToConstant: 480),
        ]
        for view in [titleLabel, bar, counts, lastLabel, logScroll, buttons] as [NSView] {
            constraints.append(view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40))
        }
        NSLayoutConstraint.activate(constraints)
        fitWindow()
    }

    private func fitWindow() {
        guard let window, let content = window.contentView else { return }
        content.layoutSubtreeIfNeeded()
        let size = content.fittingSize
        var frame = window.frame
        let newFrame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        frame.origin.y += frame.height - newFrame.height
        frame.size = newFrame.size
        window.setFrame(frame, display: true, animate: window.isVisible)
    }

    func start() {
        startDate = Date()
        bar.startAnimation(nil)
        timer = Timer.scheduledTimer(timeInterval: 0.5, target: self, selector: #selector(tick(_:)),
                                     userInfo: nil, repeats: true)
        updateTime()
    }

    @objc private func tick(_ timer: Timer) {
        updateTime()
    }

    func fileFinished(name: String, state: ItemState) {
        finished = min(finished + 1, total)
        if bar.isIndeterminate {
            bar.stopAnimation(nil)
            bar.isIndeterminate = false
        }
        bar.doubleValue = Double(finished)
        countLabel.stringValue = L("progress.count", finished, total)
        let mark: String
        switch state {
        case .done: mark = "✓"
        case .failed: mark = "✗"
        case .skipped: mark = "–"
        default: mark = "·"
        }
        lastLabel.stringValue = "\(mark) \(name)"
        updateTime()
    }

    func appendLog(_ line: String) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: line.hasPrefix("fail") ? NSColor.systemRed : NSColor.textColor,
        ]
        logView.textStorage?.append(NSAttributedString(string: line + "\n", attributes: attributes))
        logView.scrollToEndOfDocument(nil)
    }

    func finish(summary: String, success: Bool) {
        isDone = true
        timer?.invalidate()
        timer = nil
        bar.stopAnimation(nil)
        if bar.isIndeterminate { bar.isIndeterminate = false }
        bar.doubleValue = success ? bar.maxValue : Double(finished)
        titleLabel.stringValue = summary
        actionButton.title = L("button.close")
        actionButton.keyEquivalent = "\r"
        actionButton.isEnabled = true
        updateTime()
        if !success && logScroll.isHidden { setDetails(visible: true) }
    }

    private func updateTime() {
        let elapsed = Date().timeIntervalSince(startDate)
        var text = L("progress.elapsed", Self.format(elapsed))
        if !isDone, finished > 0, finished < total {
            let remaining = elapsed / Double(finished) * Double(total - finished)
            text += "  ·  " + L("progress.remaining", Self.format(remaining))
        }
        timeLabel.stringValue = text
    }

    private static func format(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds.rounded()))
        if value >= 3600 {
            return String(format: "%d:%02d:%02d", value / 3600, (value % 3600) / 60, value % 60)
        }
        return String(format: "%02d:%02d", value / 60, value % 60)
    }

    private func setDetails(visible: Bool) {
        disclosure.state = visible ? .on : .off
        logScroll.isHidden = !visible
        fitWindow()
    }

    @objc private func toggleDetails(_ sender: Any?) {
        setDetails(visible: disclosure.state == .on)
    }

    @objc private func toggleDetailsFromLabel(_ sender: Any?) {
        setDetails(visible: logScroll.isHidden)
    }

    @objc private func actionPressed(_ sender: Any?) {
        if isDone {
            onClose?()
            return
        }
        wasCancelled = true
        actionButton.isEnabled = false
        titleLabel.stringValue = L("progress.stopping")
        onCancel?()
    }
}
