import AppKit

struct EngineInfo: Decodable {
    let id: String
    let status: String
    let outdated: Bool?
    let fromSystem: Bool?
    let folder: String?
    let version: String?
    let downloadable: Bool
    let downloadSize: Int64?
    let installedSize: Int64?
    let unavailableReason: String?
    let converters: [String]?

    var isInstalled: Bool { status == "installed" }
    var isOwnCopy: Bool { status == "owncopy" }
    var isMissing: Bool { !isInstalled && !isOwnCopy }

    var displayName: String {
        switch id {
        case "libreoffice": return "LibreOffice"
        case "pandoc": return "Pandoc"
        case "ghostscript": return "Ghostscript"
        case "ffmpeg": return "FFmpeg"
        case "calibre": return "calibre"
        case "tesseract": return "Tesseract"
        case "whisper": return "Whisper"
        default: return id.prefix(1).uppercased() + id.dropFirst()
        }
    }

    var unlocks: String? {
        let key = "engine.unlocks." + id
        let value = L(key)
        return value == key ? nil : value
    }

    var brewCommand: String? {
        guard let reason = unavailableReason,
              let range = reason.range(of: "brew install [A-Za-z0-9@._-]+", options: .regularExpression) else { return nil }
        return String(reason[range])
    }
}

private struct EngineList: Decodable {
    let platform: String
    let engines: [EngineInfo]
}

struct EngineProgress: Decodable {
    let id: String
    let stage: String
    let component: String
    let fraction: Double
    let bytesDone: Int64
    let bytesTotal: Int64
}

struct EngineOutcome: Decodable {
    let id: String
    let state: String
    let version: String?
    let reason: String?
    let error: String?
}

extension FileeEngine {
    func loadEngines() throws -> [EngineInfo] {
        let result = try run(["engines", "--json"])
        guard result.status == 0,
              let list = try? JSONDecoder().decode(EngineList.self, from: Data(result.stdout.utf8)) else {
            throw FileeError.failed(L("engines.unsupported"))
        }
        return list.engines
    }
}

final class EngineTask {
    let id: String
    let action: String
    private let process = Process()
    private var errBuffer = Data()
    private var plainErrors: [String] = []
    var onProgress: ((EngineProgress) -> Void)?
    var onFinish: ((EngineOutcome?, String) -> Void)?

    init(executable: URL, action: String, id: String) {
        self.id = id
        self.action = action
        process.executableURL = executable
        process.arguments = ["engines", action, id, "--json"]
        process.currentDirectoryURL = FileeEngine.scratchDirectory
    }

    var isRunning: Bool { process.isRunning }

    func start() throws {
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        try process.run()

        let proc = process
        let outHandle = out.fileHandleForReading
        let errHandle = err.fileHandleForReading
        DispatchQueue.global(qos: .userInitiated).async {
            let outBox = DataBox()
            let group = DispatchGroup()
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                outBox.data = outHandle.readDataToEndOfFile()
                group.leave()
            }
            while true {
                let chunk = errHandle.availableData
                if chunk.isEmpty { break }
                DispatchQueue.main.async { self.consume(chunk) }
            }
            group.wait()
            proc.waitUntilExit()
            let outcome = try? JSONDecoder().decode(EngineOutcome.self, from: outBox.data)
            DispatchQueue.main.async {
                if !self.errBuffer.isEmpty {
                    self.handle(String(decoding: self.errBuffer, as: UTF8.self))
                    self.errBuffer.removeAll()
                }
                self.onFinish?(outcome, self.plainErrors.joined(separator: "\n"))
            }
        }
    }

    func cancel() {
        guard process.isRunning else { return }
        process.interrupt()
    }

    private func consume(_ data: Data) {
        errBuffer.append(data)
        while let newline = errBuffer.firstIndex(of: 0x0A) {
            let line = errBuffer[errBuffer.startIndex..<newline]
            errBuffer.removeSubrange(errBuffer.startIndex...newline)
            handle(String(decoding: line, as: UTF8.self))
        }
    }

    private func handle(_ raw: String) {
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }
        if line.hasPrefix("{"), let progress = try? JSONDecoder().decode(EngineProgress.self, from: Data(line.utf8)) {
            onProgress?(progress)
        } else {
            plainErrors.append(line)
        }
    }
}

final class EnginesWindowController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    var onChange: (() -> Void)?
    var canRemove: () -> Bool = { true }

    private var engines: [EngineInfo] = []
    private var task: EngineTask?
    private var loading = false

    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let messageLabel = NSTextField(wrappingLabelWithString: "")
    private let progressBar = NSProgressIndicator()
    private let progressLabel = NSTextField(labelWithString: "")
    private let cancelButton = NSButton(title: L("button.cancel"), target: nil, action: nil)
    private let refreshButton = NSButton(title: L("engines.refresh"), target: nil, action: nil)
    private let progressRow = NSStackView()

    var isBusy: Bool { task?.isRunning == true }

    convenience init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 420),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = L("engines.title")
        window.minSize = NSSize(width: 560, height: 320)
        self.init(window: window)
        window.delegate = self
        build()
        if !window.setFrameUsingName("EnginesWindow") { window.center() }
        window.setFrameAutosaveName("EnginesWindow")
    }

    private func build() {
        guard let content = window?.contentView else { return }

        let intro = NSTextField(wrappingLabelWithString: L("engines.intro"))
        intro.textColor = .secondaryLabelColor
        intro.font = .systemFont(ofSize: NSFont.smallSystemFontSize)

        let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameColumn.title = L("engines.column.engine")
        nameColumn.width = 260
        nameColumn.minWidth = 180
        let statusColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("status"))
        statusColumn.title = L("engines.column.status")
        statusColumn.width = 250
        statusColumn.minWidth = 160
        let actionColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("action"))
        actionColumn.title = ""
        actionColumn.width = 120
        actionColumn.minWidth = 120
        actionColumn.maxWidth = 140
        tableView.addTableColumn(nameColumn)
        tableView.addTableColumn(statusColumn)
        tableView.addTableColumn(actionColumn)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 46
        tableView.selectionHighlightStyle = .none
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        tableView.style = .inset

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder

        messageLabel.textColor = .secondaryLabelColor
        messageLabel.alignment = .center
        messageLabel.isHidden = true

        progressBar.isIndeterminate = false
        progressBar.minValue = 0
        progressBar.maxValue = 1
        progressBar.style = .bar
        progressBar.controlSize = .small
        progressLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        progressLabel.textColor = .secondaryLabelColor
        progressLabel.lineBreakMode = .byTruncatingTail
        progressLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        cancelButton.target = self
        cancelButton.action = #selector(cancelTask(_:))
        cancelButton.controlSize = .small

        let progressStack = NSStackView(views: [progressLabel, progressBar])
        progressStack.orientation = .vertical
        progressStack.alignment = .leading
        progressStack.spacing = 4
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        progressBar.widthAnchor.constraint(equalTo: progressStack.widthAnchor).isActive = true

        progressRow.orientation = .horizontal
        progressRow.alignment = .centerY
        progressRow.spacing = 10
        progressRow.addArrangedSubview(progressStack)
        progressRow.addArrangedSubview(cancelButton)
        progressRow.isHidden = true

        refreshButton.target = self
        refreshButton.action = #selector(refresh(_:))
        refreshButton.bezelStyle = .rounded

        let bottom = NSStackView(views: [refreshButton, progressRow])
        bottom.orientation = .horizontal
        bottom.alignment = .centerY
        bottom.spacing = 16

        for view in [intro, scrollView, messageLabel, bottom] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            intro.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            intro.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            intro.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            scrollView.topAnchor.constraint(equalTo: intro.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottom.topAnchor, constant: -12),
            messageLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
            messageLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 40),
            messageLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -40),
            bottom.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            bottom.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            bottom.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
            progressRow.widthAnchor.constraint(greaterThanOrEqualToConstant: 280),
        ])
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        if !isBusy { reload() }
    }

    func reload() {
        guard !loading else { return }
        guard FileeEngine.shared.executableURL ?? FileeEngine.shared.locate() != nil else {
            show(message: L("error.notFound"))
            return
        }
        loading = true
        refreshButton.isEnabled = false
        if engines.isEmpty { show(message: L("engines.loading")) }
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try FileeEngine.shared.loadEngines() }
            DispatchQueue.main.async {
                self.loading = false
                self.refreshButton.isEnabled = !self.isBusy
                switch result {
                case .success(let list):
                    self.engines = list
                    self.show(message: list.isEmpty ? L("engines.empty") : nil)
                case .failure(let error):
                    self.engines = []
                    self.show(message: error.localizedDescription)
                }
                self.tableView.reloadData()
            }
        }
    }

    private func show(message: String?) {
        messageLabel.stringValue = message ?? ""
        messageLabel.isHidden = message == nil
        scrollView.isHidden = message != nil
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        engines.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let column = tableColumn?.identifier.rawValue else { return nil }
        let engine = engines[row]
        switch column {
        case "name":
            return twoLines(engine.displayName, engine.unlocks, bold: true)
        case "status":
            let (status, detail) = describe(engine)
            let view = twoLines(status, detail, bold: false)
            view.toolTip = engine.unavailableReason ?? engine.folder
            return view
        default:
            return actionView(for: engine, row: row)
        }
    }

    private func describe(_ engine: EngineInfo) -> (String, String?) {
        let size = { (bytes: Int64?) in ByteCountFormatter.string(fromByteCount: bytes ?? 0, countStyle: .file) }
        if task?.id == engine.id {
            return (task?.action == "remove" ? L("engines.status.removing") : L("engines.status.installing"), nil)
        }
        if engine.isInstalled {
            let version = engine.version ?? ""
            if engine.outdated == true {
                return (L("engines.status.outdated"), L("engines.detail.update", version, size(engine.downloadSize)))
            }
            return (L("engines.status.installed", version), L("engines.detail.onDisk", size(engine.installedSize)))
        }
        if engine.isOwnCopy {
            let status = engine.fromSystem == true ? L("engines.status.system") : L("engines.status.ownCopy")
            return (status, engine.folder.map { ($0 as NSString).abbreviatingWithTildeInPath })
        }
        if engine.downloadable {
            return (L("engines.status.notInstalled"),
                    L("engines.detail.download", size(engine.downloadSize), size(engine.installedSize)))
        }
        if let command = engine.brewCommand {
            return (L("engines.status.notInstalled"), L("engines.detail.brew", command))
        }
        return (L("engines.status.notInstalled"), engine.unavailableReason)
    }

    private func twoLines(_ title: String, _ detail: String?, bold: Bool) -> NSView {
        let top = NSTextField(labelWithString: title)
        top.font = bold ? .boldSystemFont(ofSize: NSFont.systemFontSize) : .systemFont(ofSize: NSFont.systemFontSize)
        top.lineBreakMode = .byTruncatingTail
        let stack = NSStackView(views: [top])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 1
        if let detail, !detail.isEmpty {
            let bottom = NSTextField(labelWithString: detail)
            bottom.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            bottom.textColor = .secondaryLabelColor
            bottom.lineBreakMode = .byTruncatingTail
            bottom.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            stack.addArrangedSubview(bottom)
        }
        top.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let cell = NSTableCellView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -4),
            stack.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    private func actionView(for engine: EngineInfo, row: Int) -> NSView {
        let cell = NSTableCellView()
        var title: String?
        if engine.isInstalled {
            title = engine.outdated == true ? L("engines.action.update") : L("engines.action.remove")
        } else if engine.isOwnCopy && engine.fromSystem == true && engine.downloadable {
            title = nil
        } else if engine.isMissing && engine.downloadable {
            title = L("engines.action.install")
        } else if engine.isMissing && engine.brewCommand != nil {
            title = L("engines.action.copyCommand")
        }
        guard let title else { return cell }
        let button = NSButton(title: title, target: self, action: #selector(actionPressed(_:)))
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.tag = row
        button.isEnabled = !isBusy || (engine.isMissing && !engine.downloadable)
        button.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(button)
        NSLayoutConstraint.activate([
            button.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
            button.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    @objc private func actionPressed(_ sender: NSButton) {
        guard engines.indices.contains(sender.tag) else { return }
        let engine = engines[sender.tag]
        if engine.isInstalled && engine.outdated != true {
            confirmRemove(engine)
        } else if engine.downloadable {
            start("install", engine)
        } else if let command = engine.brewCommand {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command, forType: .string)
            progressRow.isHidden = false
            progressBar.isHidden = true
            cancelButton.isHidden = true
            progressLabel.stringValue = L("engines.copied", command)
        }
    }

    private func confirmRemove(_ engine: EngineInfo) {
        guard let window else { return }
        guard canRemove() else {
            let alert = NSAlert()
            alert.messageText = L("engines.removeBusy")
            alert.beginSheetModal(for: window)
            return
        }
        let alert = NSAlert()
        alert.messageText = L("engines.removeTitle", engine.displayName)
        alert.informativeText = L("engines.removeBody")
        alert.addButton(withTitle: L("engines.action.remove"))
        alert.addButton(withTitle: L("button.cancel"))
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            self.start("remove", engine)
        }
    }

    private func start(_ action: String, _ engine: EngineInfo) {
        guard !isBusy, let executable = FileeEngine.shared.executableURL ?? FileeEngine.shared.locate() else { return }
        let task = EngineTask(executable: executable, action: action, id: engine.id)
        task.onProgress = { [weak self] progress in self?.showProgress(progress, engine) }
        task.onFinish = { [weak self] outcome, errors in self?.finished(engine, outcome, errors) }
        self.task = task
        progressRow.isHidden = false
        progressBar.isHidden = false
        progressBar.isIndeterminate = true
        progressBar.startAnimation(nil)
        cancelButton.isHidden = action == "remove"
        cancelButton.isEnabled = true
        progressLabel.stringValue = action == "remove" ? L("engines.removing", engine.displayName)
                                                       : L("engines.preparing", engine.displayName)
        refreshButton.isEnabled = false
        tableView.reloadData()
        do {
            try task.start()
        } catch {
            self.task = nil
            finishUI(message: error.localizedDescription)
        }
    }

    private func showProgress(_ progress: EngineProgress, _ engine: EngineInfo) {
        if progress.stage == "downloading" && progress.bytesTotal > 0 {
            progressBar.isIndeterminate = false
            progressBar.stopAnimation(nil)
            progressBar.doubleValue = progress.fraction
            let done = ByteCountFormatter.string(fromByteCount: progress.bytesDone, countStyle: .file)
            let total = ByteCountFormatter.string(fromByteCount: progress.bytesTotal, countStyle: .file)
            progressLabel.stringValue = L("engines.downloading", engine.displayName, done, total,
                                          Int(progress.fraction * 100))
        } else {
            progressBar.isIndeterminate = true
            progressBar.startAnimation(nil)
            progressLabel.stringValue = L("engines.unpacking", engine.displayName)
        }
    }

    private func finished(_ engine: EngineInfo, _ outcome: EngineOutcome?, _ errors: String) {
        task = nil
        let message: String
        switch outcome?.state {
        case "installed":
            message = L("engines.done.installed", engine.displayName, outcome?.version ?? "")
        case "removed":
            message = L("engines.done.removed", engine.displayName)
        case "skipped":
            message = outcome?.reason ?? L("engines.done.skipped", engine.displayName)
        case "cancelled":
            message = L("engines.done.cancelled", engine.displayName)
        case "failed":
            message = L("engines.done.failed", engine.displayName, outcome?.error ?? errors)
        default:
            message = L("engines.done.failed", engine.displayName, errors.isEmpty ? "?" : errors)
        }
        finishUI(message: message)
        if outcome?.state == "installed" || outcome?.state == "removed" {
            onChange?()
        }
        reload()
    }

    private func finishUI(message: String) {
        progressBar.stopAnimation(nil)
        progressBar.isHidden = true
        cancelButton.isHidden = true
        progressLabel.stringValue = message
        refreshButton.isEnabled = true
        tableView.reloadData()
    }

    @objc private func cancelTask(_ sender: Any?) {
        cancelButton.isEnabled = false
        progressLabel.stringValue = L("progress.stopping")
        task?.cancel()
    }

    @objc private func refresh(_ sender: Any?) {
        progressRow.isHidden = true
        reload()
    }

    func cancelForQuit() {
        task?.cancel()
    }
}
