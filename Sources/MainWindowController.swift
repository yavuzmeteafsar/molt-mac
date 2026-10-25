import AppKit

final class FileItem {
    let url: URL
    let formatId: String
    let size: Int64
    var state: ItemState = .pending
    var outputs: [URL] = []
    var message: String?

    init(url: URL, formatId: String, size: Int64) {
        self.url = url
        self.formatId = formatId
        self.size = size
    }
}

private final class TargetBox: @unchecked Sendable {
    private var values: [TargetSet?]
    private let lock = NSLock()

    init(count: Int) {
        values = Array(repeating: nil, count: count)
    }

    func set(_ value: TargetSet, at index: Int) {
        lock.lock()
        values[index] = value
        lock.unlock()
    }

    func get(_ index: Int) -> TargetSet {
        lock.lock()
        defer { lock.unlock() }
        return values[index] ?? TargetSet(now: [], withEngines: [])
    }
}

private enum Prefs {
    static let lastTarget = "LastTarget"
    static let useCustomFolder = "UseCustomFolder"
    static let customFolder = "CustomFolder"
    static let quality = "Quality"
    static let overwrite = "Overwrite"
    static let keepDates = "KeepDates"
}

private extension NSToolbarItem.Identifier {
    static let addFiles = NSToolbarItem.Identifier("addFiles")
    static let removeFiles = NSToolbarItem.Identifier("removeFiles")
    static let clearFiles = NSToolbarItem.Identifier("clearFiles")
    static let revealFiles = NSToolbarItem.Identifier("revealFiles")
    static let convertFiles = NSToolbarItem.Identifier("convertFiles")
}

final class MainWindowController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate,
    NSToolbarDelegate, NSMenuDelegate, NSMenuItemValidation, NSToolbarItemValidation {

    private(set) var items: [FileItem] = []

    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let dropHint = DropHintView()
    private let targetButton = NSButton(title: "", target: nil, action: nil)
    private var currentTarget: String?
    private var readyTargets: Set<String> = []
    private var engineTargets: Set<String> = []
    private var pickerPopover: NSPopover?
    private let qualitySlider = NSSlider(value: 85, minValue: 1, maxValue: 100, target: nil, action: nil)
    private let qualityValue = NSTextField(labelWithString: "85")
    private let qualityGroup = NSStackView()
    private let outputPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let overwriteCheck = NSButton(checkboxWithTitle: L("option.overwrite"), target: nil, action: nil)
    private let keepDatesCheck = NSButton(checkboxWithTitle: L("option.keepDates"), target: nil, action: nil)
    private let convertButton = NSButton(title: L("button.convert"), target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")

    private var targets: [String: TargetSet] = [:]
    private var loadingFormats = Set<String>()
    private var pendingURLs: [URL] = []
    private var currentRun: ConversionRun?
    private var runningTarget: String?
    private var progress: ProgressSheetController?
    private var engineReady = false
    private var engineMessage: String?
    private var notice: String?
    private var useCustomFolder = false
    private var customFolder: URL?

    private let lossyTargets: Set<String> = ["jpg", "webp", "avif", "heic", "jxl", "jp2"]

    var isConverting: Bool { currentRun != nil }

    convenience init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 880, height: 560),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = AppInfo.name
        window.minSize = NSSize(width: 700, height: 420)
        window.toolbarStyle = .expanded
        self.init(window: window)
        window.delegate = self
        restorePreferences()
        setupToolbar()
        setupContent()
        if !window.setFrameUsingName("MainWindow") { window.center() }
        window.setFrameAutosaveName("MainWindow")
        refreshAll()
    }


    private func setupToolbar() {
        let toolbar = NSToolbar(identifier: "MainToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        window?.toolbar = toolbar
    }

    private func column(_ id: String, _ title: String, width: CGFloat, minWidth: CGFloat, sortKey: String?) -> NSTableColumn {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
        column.title = title
        column.width = width
        column.minWidth = minWidth
        if let sortKey {
            column.sortDescriptorPrototype = NSSortDescriptor(key: sortKey, ascending: true)
        }
        return column
    }

    private func setupContent() {
        guard let content = window?.contentView else { return }

        let sizeColumn = column("size", L("column.size"), width: 90, minWidth: 70, sortKey: "size")
        sizeColumn.headerCell.alignment = .right
        for item in [
            column("name", L("column.name"), width: 340, minWidth: 160, sortKey: "name"),
            column("type", L("column.type"), width: 90, minWidth: 60, sortKey: "type"),
            sizeColumn,
            column("status", L("column.status"), width: 260, minWidth: 120, sortKey: nil),
        ] {
            tableView.addTableColumn(item)
        }
        tableView.style = .fullWidth
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = true
        tableView.rowHeight = 24
        tableView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(openClicked(_:))
        tableView.registerForDraggedTypes([.fileURL])
        tableView.setDraggingSourceOperationMask(.copy, forLocal: false)
        tableView.autosaveName = "FileTable"
        tableView.autosaveTableColumns = true
        let menu = NSMenu()
        menu.delegate = self
        tableView.menu = menu

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        dropHint.translatesAutoresizingMaskIntoConstraints = false
        dropHint.onDrop = { [weak self] urls in self?.addURLs(urls) }
        dropHint.onClick = { [weak self] in self?.addFiles(nil) }
        dropHint.canAccept = { [weak self] in
            guard let self else { return false }
            return self.currentRun == nil
        }

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        let bar = buildBottomBar()

        content.addSubview(scrollView)
        content.addSubview(dropHint)
        content.addSubview(separator)
        content.addSubview(bar)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: content.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: separator.topAnchor),

            dropHint.topAnchor.constraint(equalTo: scrollView.topAnchor),
            dropHint.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            dropHint.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            dropHint.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),

            separator.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bar.topAnchor),

            bar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
    }

    private func buildBottomBar() -> NSView {
        let bar = NSView()
        bar.translatesAutoresizingMaskIntoConstraints = false

        let targetLabel = NSTextField(labelWithString: L("label.target"))
        targetLabel.alignment = .right
        targetButton.bezelStyle = .rounded
        targetButton.image = NSImage(systemSymbolName: "chevron.up.chevron.down", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 9, weight: .semibold))
        targetButton.imagePosition = .imageTrailing
        targetButton.alignment = .left
        targetButton.target = self
        targetButton.action = #selector(showPicker(_:))

        let qualityLabel = NSTextField(labelWithString: L("label.quality"))
        qualitySlider.target = self
        qualitySlider.action = #selector(qualityChanged(_:))
        qualitySlider.isContinuous = true
        qualityValue.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        qualityValue.alignment = .right
        qualityGroup.orientation = .horizontal
        qualityGroup.spacing = 6
        for view in [qualityLabel, qualitySlider, qualityValue] as [NSView] {
            qualityGroup.addArrangedSubview(view)
        }

        convertButton.target = self
        convertButton.action = #selector(convert(_:))
        convertButton.keyEquivalent = "\r"
        convertButton.bezelStyle = .rounded
        convertButton.controlSize = .large
        convertButton.setContentHuggingPriority(.required, for: .horizontal)

        let spacer1 = NSView()
        spacer1.setContentHuggingPriority(.init(1), for: .horizontal)
        let row1 = NSStackView(views: [targetLabel, targetButton, qualityGroup, spacer1, convertButton])
        row1.orientation = .horizontal
        row1.alignment = .centerY
        row1.spacing = 10
        row1.setCustomSpacing(18, after: targetButton)

        let outputLabel = NSTextField(labelWithString: L("label.output"))
        outputLabel.alignment = .right
        outputPopup.autoenablesItems = false
        outputPopup.target = self
        outputPopup.action = #selector(outputChanged(_:))
        overwriteCheck.target = self
        overwriteCheck.action = #selector(optionChanged(_:))
        keepDatesCheck.target = self
        keepDatesCheck.action = #selector(optionChanged(_:))

        let spacer2 = NSView()
        spacer2.setContentHuggingPriority(.init(1), for: .horizontal)
        let row2 = NSStackView(views: [outputLabel, outputPopup, overwriteCheck, keepDatesCheck, spacer2])
        row2.orientation = .horizontal
        row2.alignment = .centerY
        row2.spacing = 10
        row2.setCustomSpacing(18, after: outputPopup)

        statusLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.setContentCompressionResistancePriority(.init(1), for: .horizontal)

        let stack = NSStackView(views: [row1, row2, statusLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 10, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: bar.topAnchor),
            stack.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
            row1.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
            row2.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
            statusLabel.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
            outputLabel.widthAnchor.constraint(equalTo: targetLabel.widthAnchor),
            targetButton.widthAnchor.constraint(equalToConstant: 240),
            outputPopup.widthAnchor.constraint(equalTo: targetButton.widthAnchor),
            qualitySlider.widthAnchor.constraint(equalToConstant: 130),
            qualityValue.widthAnchor.constraint(equalToConstant: 30),
        ])
        return bar
    }

    private func restorePreferences() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Prefs.quality) != nil {
            qualitySlider.integerValue = min(100, max(1, defaults.integer(forKey: Prefs.quality)))
        }
        qualityValue.stringValue = String(qualitySlider.integerValue)
        overwriteCheck.state = defaults.bool(forKey: Prefs.overwrite) ? .on : .off
        keepDatesCheck.state = defaults.bool(forKey: Prefs.keepDates) ? .on : .off
        if let path = defaults.string(forKey: Prefs.customFolder),
           FileManager.default.fileExists(atPath: path) {
            customFolder = URL(fileURLWithPath: path, isDirectory: true)
        }
        useCustomFolder = defaults.bool(forKey: Prefs.useCustomFolder) && customFolder != nil
        rebuildOutputMenu()
    }


    func startEngine() {
        engineReady = false
        guard FileeEngine.shared.locate() != nil else {
            engineMessage = L("status.missingEngine", AppInfo.name)
            refreshAll()
            showMissingEngine()
            return
        }
        engineMessage = L("status.loadingEngine")
        refreshAll()
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try FileeEngine.shared.loadFormats() }
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self.engineReady = true
                    self.engineMessage = L("status.engineReady", FileeEngine.shared.version ?? "Filee")
                    let waiting = self.pendingURLs
                    self.pendingURLs = []
                    if !waiting.isEmpty { self.addURLs(waiting) }
                case .failure(let error):
                    self.engineMessage = L("status.engineError", error.localizedDescription)
                }
                self.refreshAll()
            }
        }
    }

    private func showMissingEngine() {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = L("missing.title")
        alert.informativeText = L("missing.body", AppInfo.name)
        alert.addButton(withTitle: L("missing.download"))
        alert.addButton(withTitle: L("missing.locate"))
        alert.addButton(withTitle: L("button.cancel"))
        alert.beginSheetModal(for: window) { response in
            switch response {
            case .alertFirstButtonReturn:
                NSWorkspace.shared.open(AppInfo.fileeReleases)
            case .alertSecondButtonReturn:
                DispatchQueue.main.async { self.locateFilee(nil) }
            default:
                break
            }
        }
    }

    @objc func locateFilee(_ sender: Any?) {
        guard let window, currentRun == nil else { return }
        let panel = NSOpenPanel()
        panel.message = L("missing.panelMessage")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let picked = panel.url else { return }
            let cli = FileeEngine.cliURL(fromUserChoice: picked)
            guard FileManager.default.isExecutableFile(atPath: cli.path) else {
                let alert = NSAlert()
                alert.messageText = L("missing.invalid")
                alert.runModal()
                return
            }
            UserDefaults.standard.set(cli.path, forKey: FileeEngine.customPathKey)
            self.targets.removeAll()
            self.startEngine()
        }
    }


    func addURLs(_ urls: [URL]) {
        guard engineReady else {
            pendingURLs += urls
            return
        }
        guard currentRun == nil else {
            NSSound.beep()
            return
        }
        var known = Set(items.map { $0.url.path })
        var added: [FileItem] = []
        var unknown = 0
        for url in expand(urls) {
            let clean = url.standardizedFileURL
            if known.contains(clean.path) { continue }
            guard let formatId = FileeEngine.shared.detect(clean) else {
                unknown += 1
                continue
            }
            let size = Int64((try? clean.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            known.insert(clean.path)
            added.append(FileItem(url: clean, formatId: formatId, size: size))
        }
        notice = unknown > 0 ? L("status.skippedUnknown", unknown) : nil
        guard !added.isEmpty else {
            refreshAll()
            return
        }
        items += added
        applySort()
        tableView.reloadData()
        window?.makeFirstResponder(tableView)
        loadTargets(Set(added.map(\.formatId)))
        refreshAll()
    }

    private func expand(_ urls: [URL]) -> [URL] {
        let fm = FileManager.default
        var result: [URL] = []
        for url in urls {
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            if !isDirectory.boolValue {
                result.append(url)
                continue
            }
            if NSWorkspace.shared.isFilePackage(atPath: url.path) { continue }
            guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey],
                                                 options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let file as URL in enumerator {
                if (try? file.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
                    result.append(file)
                }
            }
        }
        return result
    }

    private func loadTargets(_ ids: Set<String>) {
        let needed = ids.subtracting(targets.keys).subtracting(loadingFormats)
        guard !needed.isEmpty else { return }
        loadingFormats.formUnion(needed)
        let list = Array(needed)
        let box = TargetBox(count: list.count)
        DispatchQueue.global(qos: .userInitiated).async {
            DispatchQueue.concurrentPerform(iterations: list.count) { index in
                let set = (try? FileeEngine.shared.targets(for: list[index])) ?? TargetSet(now: [], withEngines: [])
                box.set(set, at: index)
            }
            DispatchQueue.main.async {
                for (index, id) in list.enumerated() {
                    self.targets[id] = box.get(index)
                }
                self.loadingFormats.subtract(needed)
                self.refreshAll()
            }
        }
    }

    private func targetRows() -> IndexSet {
        let clicked = tableView.clickedRow
        let selected = tableView.selectedRowIndexes
        if clicked >= 0 && !selected.contains(clicked) { return IndexSet(integer: clicked) }
        return selected
    }


    @objc func addFiles(_ sender: Any?) {
        guard let window, engineReady, currentRun == nil else {
            if !engineReady && FileeEngine.shared.executableURL == nil { showMissingEngine() }
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.beginSheetModal(for: window) { response in
            guard response == .OK else { return }
            self.addURLs(panel.urls)
        }
    }

    @objc func removeSelected(_ sender: Any?) {
        guard currentRun == nil else { return }
        let rows = targetRows()
        guard !rows.isEmpty else { return }
        for index in rows.reversed() where index < items.count {
            items.remove(at: index)
        }
        tableView.reloadData()
        notice = nil
        refreshAll()
    }

    @objc func clearAll(_ sender: Any?) {
        guard currentRun == nil, !items.isEmpty else { return }
        items.removeAll()
        tableView.reloadData()
        notice = nil
        refreshAll()
    }

    @objc func revealInFinder(_ sender: Any?) {
        let rows = targetRows()
        let chosen = rows.isEmpty ? items : rows.compactMap { $0 < items.count ? items[$0] : nil }
        let urls = chosen.flatMap { $0.outputs.isEmpty ? [$0.url] : $0.outputs }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    @objc func revealSource(_ sender: Any?) {
        let urls = targetRows().compactMap { $0 < items.count ? items[$0].url : nil }
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    @objc func openSource(_ sender: Any?) {
        for index in targetRows() where index < items.count {
            NSWorkspace.shared.open(items[index].url)
        }
    }

    @objc func openOutput(_ sender: Any?) {
        for index in targetRows() where index < items.count {
            if let first = items[index].outputs.first { NSWorkspace.shared.open(first) }
        }
    }

    @objc private func openClicked(_ sender: Any?) {
        let row = tableView.clickedRow
        guard row >= 0, row < items.count else { return }
        let item = items[row]
        NSWorkspace.shared.open(item.outputs.first ?? item.url)
    }

    @objc private func showPicker(_ sender: Any?) {
        if let open = pickerPopover, open.isShown {
            open.performClose(nil)
            return
        }
        guard currentRun == nil, !readyTargets.isEmpty || !engineTargets.isEmpty else { return }
        let picker = FormatPickerController(ready: readyTargets, needsEngine: engineTargets, selected: currentTarget)
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = picker
        picker.onPick = { [weak self, weak popover] id in
            popover?.performClose(nil)
            self?.choose(id)
        }
        pickerPopover = popover
        popover.show(relativeTo: targetButton.bounds, of: targetButton, preferredEdge: .maxY)
    }

    private func choose(_ id: String) {
        guard id != currentTarget else { return }
        currentTarget = id
        targetChanged(nil)
    }

    @objc private func targetChanged(_ sender: Any?) {
        if let id = selectedTarget {
            UserDefaults.standard.set(id, forKey: Prefs.lastTarget)
        }
        for item in items where item.state != .pending {
            item.state = .pending
            item.outputs = []
            item.message = nil
        }
        tableView.reloadData()
        refreshAll()
    }

    @objc private func qualityChanged(_ sender: Any?) {
        qualityValue.stringValue = String(qualitySlider.integerValue)
        UserDefaults.standard.set(qualitySlider.integerValue, forKey: Prefs.quality)
    }

    @objc private func optionChanged(_ sender: Any?) {
        UserDefaults.standard.set(overwriteCheck.state == .on, forKey: Prefs.overwrite)
        UserDefaults.standard.set(keepDatesCheck.state == .on, forKey: Prefs.keepDates)
    }

    @objc private func outputChanged(_ sender: Any?) {
        switch outputPopup.selectedTag() {
        case 1:
            chooseOutputFolder()
        case 2:
            useCustomFolder = true
            saveOutputPreference()
        default:
            useCustomFolder = false
            saveOutputPreference()
        }
    }

    private func chooseOutputFolder() {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = L("output.panelPrompt")
        if let customFolder { panel.directoryURL = customFolder }
        panel.beginSheetModal(for: window) { response in
            if response == .OK, let url = panel.url {
                self.customFolder = url
                self.useCustomFolder = true
                self.saveOutputPreference()
            }
            self.rebuildOutputMenu()
        }
    }

    private func saveOutputPreference() {
        UserDefaults.standard.set(useCustomFolder, forKey: Prefs.useCustomFolder)
        UserDefaults.standard.set(customFolder?.path, forKey: Prefs.customFolder)
    }

    @objc func convert(_ sender: Any?) {
        guard currentRun == nil, let window, let target = selectedTarget,
              let executable = FileeEngine.shared.executableURL else {
            NSSound.beep()
            return
        }
        var batch = items.filter { $0.state != .done }
        if batch.isEmpty { batch = items }
        guard !batch.isEmpty else { return }

        for item in batch {
            item.state = .running
            item.outputs = []
            item.message = nil
        }
        tableView.reloadData()
        notice = nil

        var arguments = ["convert"] + batch.map(\.url.path) + ["--to", target]
        if useCustomFolder, let customFolder { arguments += ["--output", customFolder.path] }
        if !qualityGroup.isHidden { arguments += ["--quality", String(qualitySlider.integerValue)] }
        if overwriteCheck.state == .on { arguments.append("--overwrite") }
        if keepDatesCheck.state == .on { arguments.append("--keep-dates") }

        let targetName = FileeEngine.shared.info(target)?.displayName ?? target.uppercased()
        let sheet = ProgressSheetController(total: batch.count, title: L("progress.title", targetName))
        let run = ConversionRun(executable: executable, arguments: arguments, sources: batch.map(\.url.path))
        sheet.onCancel = { [weak run] in run?.cancel() }
        sheet.onClose = { [weak self] in self?.closeProgress() }
        run.onLine = { [weak sheet] line in sheet?.appendLog(line) }
        run.onResult = { [weak self] result in self?.apply(result) }
        run.onExit = { [weak self] status, errors in
            self?.finished(status: status, errors: errors, batch: batch)
        }
        currentRun = run
        runningTarget = target
        progress = sheet
        refreshAll()

        if let sheetWindow = sheet.window { window.beginSheet(sheetWindow) }
        sheet.start()
        do {
            try run.start()
        } catch {
            sheet.appendLog(error.localizedDescription)
            finished(status: 2, errors: error.localizedDescription, batch: batch)
        }
    }

    func cancelConversion() {
        currentRun?.cancel()
    }

    private func apply(_ result: LineResult) {
        guard let index = items.firstIndex(where: { $0.url.path == result.source }) else { return }
        let item = items[index]
        guard item.state == .running else { return }
        item.state = result.state
        item.outputs = result.outputs.map { URL(fileURLWithPath: $0) }
        item.message = result.message
        if result.state == .done, runningTarget == FileeEngine.folderId {
            item.outputs = item.outputs.map(tidyExtraction)
        }
        tableView.reloadData(forRowIndexes: IndexSet(integer: index),
                             columnIndexes: IndexSet(integersIn: 0..<tableView.numberOfColumns))
        progress?.fileFinished(name: item.url.lastPathComponent, state: result.state)
    }

    private func tidyExtraction(_ folder: URL) -> URL {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else { return folder }

        let junk = folder.appendingPathComponent("__MACOSX")
        if fm.fileExists(atPath: junk.path) { try? fm.removeItem(at: junk) }
        let dsStore = folder.appendingPathComponent(".DS_Store")
        if fm.fileExists(atPath: dsStore.path) { try? fm.removeItem(at: dsStore) }

        guard let children = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil),
              children.count == 1, let only = children.first else { return folder }

        let parent = folder.deletingLastPathComponent()
        let temporary = parent.appendingPathComponent(".molt-\(UUID().uuidString)")
        do {
            try fm.moveItem(at: only, to: temporary)
            try fm.removeItem(at: folder)
            let destination = uniqueURL(for: only.lastPathComponent, in: parent)
            try fm.moveItem(at: temporary, to: destination)
            return destination
        } catch {
            if fm.fileExists(atPath: temporary.path) {
                if !fm.fileExists(atPath: folder.path) {
                    try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
                }
                try? fm.moveItem(at: temporary, to: folder.appendingPathComponent(only.lastPathComponent))
            }
            return folder
        }
    }

    private func uniqueURL(for name: String, in folder: URL) -> URL {
        let fm = FileManager.default
        var candidate = folder.appendingPathComponent(name)
        guard fm.fileExists(atPath: candidate.path) else { return candidate }
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var index = 2
        repeat {
            let numbered = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            candidate = folder.appendingPathComponent(numbered)
            index += 1
        } while fm.fileExists(atPath: candidate.path)
        return candidate
    }

    private func finished(status: Int32, errors: String, batch: [FileItem]) {
        let cancelled = progress?.wasCancelled ?? false
        let errorText = errors.trimmingCharacters(in: .whitespacesAndNewlines)
        for item in batch where item.state == .running {
            if cancelled {
                item.state = .cancelled
            } else {
                item.state = .failed
                item.message = errorText.isEmpty ? L("status.noResult") : errorText
            }
        }
        currentRun = nil
        runningTarget = nil
        tableView.reloadData()

        let done = batch.filter { $0.state == .done }.count
        let failed = batch.filter { $0.state == .failed }.count
        let skipped = batch.filter { $0.state == .skipped }.count
        var summary: String
        if status == 2 && done == 0 {
            summary = L("progress.summary.error")
        } else if cancelled {
            summary = L("progress.summary.cancelled", done)
        } else if failed > 0 {
            summary = L("progress.summary.mixed", done, failed)
        } else {
            summary = L("progress.summary.ok", done)
        }
        if skipped > 0 && !cancelled { summary += L("progress.summary.skipped", skipped) }
        if !errorText.isEmpty { progress?.appendLog(errorText) }

        let success = failed == 0 && !cancelled && status != 2
        progress?.finish(summary: summary, success: success)
        notice = summary
        refreshAll()

        NSSound(named: success ? "Glass" : "Basso")?.play()
        if !NSApp.isActive { NSApp.requestUserAttention(.informationalRequest) }
        if success && skipped == 0, let sheet = progress {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                guard let self, self.progress === sheet else { return }
                self.closeProgress()
            }
        }
    }

    private func closeProgress() {
        guard let sheet = progress else { return }
        progress = nil
        if let sheetWindow = sheet.window { window?.endSheet(sheetWindow) }
    }


    private var selectedTarget: String? {
        guard let currentTarget, readyTargets.contains(currentTarget) else { return nil }
        return currentTarget
    }

    private func refreshAll() {
        scrollView.isHidden = items.isEmpty
        dropHint.isHidden = !items.isEmpty
        rebuildTargetMenu()
        qualityGroup.isHidden = !(selectedTarget.map { lossyTargets.contains($0) } ?? false)
        convertButton.isEnabled = currentRun == nil && selectedTarget != nil && !items.isEmpty
        targetButton.isEnabled = currentRun == nil && (!readyTargets.isEmpty || !engineTargets.isEmpty)
        outputPopup.isEnabled = currentRun == nil
        overwriteCheck.isEnabled = currentRun == nil
        keepDatesCheck.isEnabled = currentRun == nil
        updateStatus()
        window?.toolbar?.validateVisibleItems()
    }

    private func updateStatus() {
        var parts: [String] = []
        if !items.isEmpty {
            let total = items.reduce(Int64(0)) { $0 + $1.size }
            let size = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
            parts.append(items.count == 1 ? L("status.summaryFile", size) : L("status.summaryFiles", items.count, size))
        }
        if let notice { parts.append(notice) }
        if parts.isEmpty || !engineReady, let engineMessage { parts.append(engineMessage) }
        statusLabel.stringValue = parts.joined(separator: "  ·  ")
    }

    private func placeholder(_ title: String) {
        readyTargets = []
        engineTargets = []
        targetButton.title = title
    }

    private func rebuildTargetMenu() {
        let remembered = currentTarget ?? UserDefaults.standard.string(forKey: Prefs.lastTarget)
        guard engineReady else { return placeholder(L("target.waiting")) }
        let ids = Set(items.map(\.formatId))
        guard !ids.isEmpty else { return placeholder(L("target.addFiles")) }
        guard ids.isSubset(of: Set(targets.keys)) else { return placeholder(L("target.loading")) }

        var available: Set<String>?
        var reachable: Set<String>?
        for id in ids {
            guard let set = targets[id] else { continue }
            let now = Set(set.now)
            let all = now.union(set.withEngines)
            available = available.map { $0.intersection(now) } ?? now
            reachable = reachable.map { $0.intersection(all) } ?? all
        }
        readyTargets = available ?? []
        engineTargets = (reachable ?? []).subtracting(readyTargets)
        guard !readyTargets.isEmpty || !engineTargets.isEmpty else { return placeholder(L("target.none")) }

        if let remembered, readyTargets.contains(remembered) {
            currentTarget = remembered
        } else {
            currentTarget = defaultTarget(in: readyTargets)
        }
        if let currentTarget, let info = FileeEngine.shared.info(currentTarget) {
            targetButton.title = info.displayName
        } else {
            targetButton.title = L("target.choose")
        }
    }

    private static let preferredTargets = [FileeEngine.folderId, "pdf", "jpg", "png", "mp4", "mp3", "docx",
                                           "xlsx", "epub", "txt", "m4a", "webp", "zip"]

    private func defaultTarget(in set: Set<String>) -> String? {
        if let preferred = Self.preferredTargets.first(where: set.contains) { return preferred }
        let infos = set.compactMap { FileeEngine.shared.info($0) }
        for category in FormatPickerController.categoryOrder {
            let match = infos.filter { $0.category == category }
                .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
            if let first = match.first { return first.id }
        }
        return set.sorted().first
    }

    private func rebuildOutputMenu() {
        outputPopup.removeAllItems()
        guard let menu = outputPopup.menu else { return }
        let iconSize = NSSize(width: 16, height: 16)

        let next = NSMenuItem(title: L("output.nextToSource"), action: nil, keyEquivalent: "")
        next.tag = 0
        next.image = NSImage(systemSymbolName: "arrow.turn.down.right", accessibilityDescription: nil)
        menu.addItem(next)

        if let customFolder {
            let folder = NSMenuItem(title: customFolder.lastPathComponent, action: nil, keyEquivalent: "")
            folder.tag = 2
            let icon = NSWorkspace.shared.icon(forFile: customFolder.path)
            icon.size = iconSize
            folder.image = icon
            folder.toolTip = customFolder.path
            menu.addItem(folder)
        }
        menu.addItem(.separator())
        let choose = NSMenuItem(title: L("output.choose"), action: nil, keyEquivalent: "")
        choose.tag = 1
        menu.addItem(choose)

        outputPopup.selectItem(withTag: useCustomFolder && customFolder != nil ? 2 : 0)
    }

    private func applySort() {
        guard let descriptor = tableView.sortDescriptors.first, let key = descriptor.key else { return }
        items.sort { a, b in
            let ascending: Bool
            switch key {
            case "size": ascending = a.size < b.size
            case "type": ascending = a.formatId < b.formatId
            default:
                ascending = a.url.lastPathComponent.localizedStandardCompare(b.url.lastPathComponent) == .orderedAscending
            }
            return descriptor.ascending ? ascending : !ascending
        }
    }


    func numberOfRows(in tableView: NSTableView) -> Int {
        items.count
    }

    private func cell(_ identifier: NSUserInterfaceItemIdentifier, withImage: Bool) -> NSTableCellView {
        if let reused = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView {
            return reused
        }
        let view = NSTableCellView()
        view.identifier = identifier
        let text = NSTextField(labelWithString: "")
        text.translatesAutoresizingMaskIntoConstraints = false
        text.lineBreakMode = .byTruncatingMiddle
        text.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        view.addSubview(text)
        view.textField = text
        if withImage {
            let image = NSImageView()
            image.translatesAutoresizingMaskIntoConstraints = false
            image.imageScaling = .scaleProportionallyUpOrDown
            view.addSubview(image)
            view.imageView = image
            NSLayoutConstraint.activate([
                image.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
                image.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                image.widthAnchor.constraint(equalToConstant: 18),
                image.heightAnchor.constraint(equalToConstant: 18),
                text.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 6),
            ])
        } else {
            text.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4).isActive = true
        }
        NSLayoutConstraint.activate([
            text.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
            text.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        return view
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn, row < items.count else { return nil }
        let item = items[row]
        switch tableColumn.identifier.rawValue {
        case "name":
            let view = cell(tableColumn.identifier, withImage: true)
            view.textField?.stringValue = item.url.lastPathComponent
            view.imageView?.image = NSWorkspace.shared.icon(forFile: item.url.path)
            view.toolTip = item.url.path
            return view
        case "type":
            let view = cell(tableColumn.identifier, withImage: false)
            view.textField?.stringValue = FileeEngine.shared.info(item.formatId)?.displayName ?? item.formatId.uppercased()
            view.textField?.textColor = .secondaryLabelColor
            return view
        case "size":
            let view = cell(tableColumn.identifier, withImage: false)
            view.textField?.stringValue = ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file)
            view.textField?.alignment = .right
            view.textField?.textColor = .secondaryLabelColor
            view.textField?.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            return view
        default:
            let view = cell(tableColumn.identifier, withImage: false)
            let (text, color) = statusText(item)
            view.textField?.stringValue = text
            view.textField?.textColor = color
            view.textField?.lineBreakMode = .byTruncatingTail
            view.toolTip = item.message ?? item.outputs.map(\.path).joined(separator: "\n")
            return view
        }
    }

    private func statusText(_ item: FileItem) -> (String, NSColor) {
        switch item.state {
        case .pending:
            return (L("status.pending"), .tertiaryLabelColor)
        case .running:
            return (L("status.running"), .controlAccentColor)
        case .done:
            if item.outputs.count > 1 { return (L("status.doneMany", item.outputs.count), .systemGreen) }
            return ("✓ " + (item.outputs.first?.lastPathComponent ?? ""), .systemGreen)
        case .skipped:
            return (L("status.skipped"), .systemOrange)
        case .failed:
            return (L("status.failed", item.message ?? "?"), .systemRed)
        case .cancelled:
            return (L("status.cancelled"), .secondaryLabelColor)
        }
    }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        applySort()
        tableView.reloadData()
    }

    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int,
                   proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        guard currentRun == nil, info.draggingSource as? NSTableView !== tableView else { return [] }
        tableView.setDropRow(-1, dropOperation: .on)
        return .copy
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int,
                   dropOperation: NSTableView.DropOperation) -> Bool {
        let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                       options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else { return false }
        addURLs(urls)
        return true
    }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard row < items.count else { return nil }
        let item = items[row]
        return (item.outputs.first ?? item.url) as NSURL
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        window?.toolbar?.validateVisibleItems()
    }


    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let rows = targetRows()
        guard !rows.isEmpty else { return }
        let hasOutput = rows.contains { $0 < items.count && !items[$0].outputs.isEmpty }
        func add(_ title: String, _ action: Selector, enabled: Bool = true) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.isEnabled = enabled
            menu.addItem(item)
        }
        add(L("context.open"), #selector(openSource(_:)))
        if hasOutput { add(L("context.openOutput"), #selector(openOutput(_:))) }
        menu.addItem(.separator())
        add(L("context.revealSource"), #selector(revealSource(_:)))
        if hasOutput { add(L("context.revealOutput"), #selector(revealInFinder(_:))) }
        menu.addItem(.separator())
        add(L("context.remove"), #selector(removeSelected(_:)), enabled: currentRun == nil)
    }


    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        validate(menuItem.action)
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        validate(item.action)
    }

    private func validate(_ action: Selector?) -> Bool {
        switch action {
        case #selector(addFiles(_:)):
            return currentRun == nil
        case #selector(removeSelected(_:)):
            return currentRun == nil && !targetRows().isEmpty
        case #selector(clearAll(_:)):
            return currentRun == nil && !items.isEmpty
        case #selector(convert(_:)):
            return currentRun == nil && selectedTarget != nil && !items.isEmpty
        case #selector(revealInFinder(_:)):
            return !items.isEmpty
        case #selector(locateFilee(_:)):
            return currentRun == nil
        default:
            return true
        }
    }


    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.addFiles, .removeFiles, .clearFiles, .revealFiles, .flexibleSpace, .convertFiles]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let spec: (String, String, Selector)
        switch itemIdentifier {
        case .addFiles: spec = (L("toolbar.add"), "plus", #selector(addFiles(_:)))
        case .removeFiles: spec = (L("toolbar.remove"), "minus", #selector(removeSelected(_:)))
        case .clearFiles: spec = (L("toolbar.clear"), "trash", #selector(clearAll(_:)))
        case .revealFiles: spec = (L("toolbar.reveal"), "folder", #selector(revealInFinder(_:)))
        case .convertFiles: spec = (L("toolbar.convert"), "arrow.triangle.2.circlepath", #selector(convert(_:)))
        default: return nil
        }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = spec.0
        item.paletteLabel = spec.0
        item.toolTip = spec.0
        item.image = NSImage(systemSymbolName: spec.1, accessibilityDescription: spec.0)
        item.target = self
        item.action = spec.2
        item.isBordered = true
        return item
    }
}
