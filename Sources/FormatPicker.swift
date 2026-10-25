import AppKit

final class FormatPickerController: NSViewController, NSSearchFieldDelegate {
    static let showEngineKey = "ShowEngineFormats"
    static let categoryOrder = ["Image", "Vector", "Pdf", "Document", "Spreadsheet", "Presentation", "Text",
                                "Ebook", "Hwp", "Video", "Audio", "Subtitle", "Archive", "Cad", "Font",
                                "Data", "Model3D", "Geo"]

    var onPick: ((String) -> Void)?

    private let ready: Set<String>
    private let needsEngine: Set<String>
    private let selected: String?
    private let searchField = NSSearchField()
    private let grid = NSStackView()
    private let emptyLabel = NSTextField(labelWithString: L("picker.noMatch"))
    private let engineToggle = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private var showEngine = UserDefaults.standard.bool(forKey: FormatPickerController.showEngineKey)
    private var firstMatch: String?

    private let maxRowsPerColumn = 10
    private let maxColumnsPerRow = 7
    private let columnWidth: CGFloat = 118

    init(ready: Set<String>, needsEngine: Set<String>, selected: String?) {
        self.ready = ready
        self.needsEngine = needsEngine
        self.selected = selected
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        searchField.placeholderString = L("picker.search")
        searchField.delegate = self
        searchField.sendsWholeSearchString = true
        searchField.target = self
        searchField.action = #selector(searchCommitted(_:))
        searchField.translatesAutoresizingMaskIntoConstraints = false

        grid.orientation = .vertical
        grid.alignment = .leading
        grid.spacing = 18

        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.isHidden = true

        engineToggle.title = L("picker.showEngine", needsEngine.count)
        engineToggle.state = showEngine ? .on : .off
        engineToggle.target = self
        engineToggle.action = #selector(toggleEngine(_:))
        engineToggle.controlSize = .small
        engineToggle.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        engineToggle.isHidden = needsEngine.isEmpty

        let stack = NSStackView(views: [searchField, grid, emptyLabel, engineToggle])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 12, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let root = NSView()
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            searchField.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -28),
            searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 300),
        ])
        view = root
        rebuild()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(searchField)
    }

    private func matches(_ info: FormatInfo, _ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        if info.id.lowercased().hasPrefix(query) { return true }
        if info.displayName.lowercased().contains(query) { return true }
        return info.extensions.contains { $0.hasPrefix(query) }
    }

    private func rebuild() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
        var groups: [String: [(FormatInfo, Bool)]] = [:]
        let pool = showEngine ? ready.union(needsEngine) : ready
        for id in pool {
            let info = FileeEngine.shared.info(id)
                ?? FormatInfo(id: id, displayName: id.uppercased(), category: "Other", extensions: [id], writable: true)
            guard matches(info, query) else { continue }
            groups[info.category, default: []].append((info, ready.contains(id)))
        }

        let order = Self.categoryOrder + groups.keys.filter { !Self.categoryOrder.contains($0) }.sorted()
        var groupsOfColumns: [[NSView]] = []
        firstMatch = nil
        for category in order {
            guard let entries = groups[category], !entries.isEmpty else { continue }
            let sorted = entries.sorted { a, b in
                if a.1 != b.1 { return a.1 }
                return a.0.displayName.localizedStandardCompare(b.0.displayName) == .orderedAscending
            }
            if firstMatch == nil, let first = sorted.first(where: { $0.1 }) { firstMatch = first.0.id }
            var categoryColumns: [NSView] = []
            var start = 0
            while start < sorted.count {
                let chunk = Array(sorted[start..<min(start + maxRowsPerColumn, sorted.count)])
                categoryColumns.append(column(title: start == 0 ? categoryName(category) : nil, entries: chunk))
                start += maxRowsPerColumn
            }
            groupsOfColumns.append(categoryColumns)
        }

        for view in grid.arrangedSubviews {
            grid.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        var rows: [[NSView]] = []
        var current: [NSView] = []
        for group in groupsOfColumns {
            if !current.isEmpty && current.count + group.count > maxColumnsPerRow {
                rows.append(current)
                current = []
            }
            current += group
        }
        if !current.isEmpty { rows.append(current) }
        for views in rows {
            let row = NSStackView(views: views)
            row.orientation = .horizontal
            row.alignment = .top
            row.spacing = 10
            grid.addArrangedSubview(row)
        }
        grid.isHidden = rows.isEmpty
        emptyLabel.isHidden = !rows.isEmpty

        view.layoutSubtreeIfNeeded()
        preferredContentSize = view.fittingSize
    }

    private func column(title: String?, entries: [(FormatInfo, Bool)]) -> NSView {
        let header = NSTextField(labelWithString: (title ?? " ").uppercased(with: Locale.current))
        header.font = .systemFont(ofSize: 10, weight: .semibold)
        header.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [header])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 1
        stack.setCustomSpacing(5, after: header)

        for (info, enabled) in entries {
            let button = NSButton(title: info.displayName, target: self, action: #selector(picked(_:)))
            button.bezelStyle = .recessed
            button.setButtonType(.pushOnPushOff)
            button.showsBorderOnlyWhileMouseInside = true
            button.alignment = .left
            button.font = .systemFont(ofSize: NSFont.systemFontSize)
            button.lineBreakMode = .byTruncatingTail
            button.identifier = NSUserInterfaceItemIdentifier(info.id)
            button.state = info.id == selected ? .on : .off
            button.isEnabled = enabled
            let extensions = info.extensions.prefix(4).map { "." + $0 }.joined(separator: " ")
            button.toolTip = enabled ? extensions : L("target.needsEngine") + "\n" + extensions
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: columnWidth).isActive = true
            stack.addArrangedSubview(button)
        }
        stack.widthAnchor.constraint(equalToConstant: columnWidth).isActive = true
        return stack
    }

    @objc private func picked(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue, ready.contains(id) else { return }
        onPick?(id)
    }

    @objc private func searchCommitted(_ sender: Any?) {
        guard let id = firstMatch else {
            NSSound.beep()
            return
        }
        onPick?(id)
    }

    @objc private func toggleEngine(_ sender: Any?) {
        showEngine = engineToggle.state == .on
        UserDefaults.standard.set(showEngine, forKey: Self.showEngineKey)
        rebuild()
    }

    func controlTextDidChange(_ obj: Notification) {
        rebuild()
    }
}
