import Foundation

struct FormatInfo {
    let id: String
    let displayName: String
    let category: String
    let extensions: [String]
    let writable: Bool
}

struct TargetSet {
    let now: [String]
    let withEngines: [String]
}

enum FileeError: LocalizedError {
    case notFound
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .notFound: return L("error.notFound")
        case .failed(let message): return message
        }
    }
}

final class DataBox: @unchecked Sendable {
    var data = Data()
}

final class FileeEngine {
    static let shared = FileeEngine()
    static let customPathKey = "FileeCLIPath"
    static let folderId = "folder"

    private(set) var executableURL: URL?
    private(set) var version: String?
    private(set) var formats: [String: FormatInfo] = [:]
    private var extensionMap: [String: String] = [:]
    private var targetCache: [String: TargetSet] = [:]
    private let lock = NSLock()

    static let scratchDirectory: URL = {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("molt-cwd-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    @discardableResult
    func locate() -> URL? {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        var candidates: [String] = []
        if let custom = UserDefaults.standard.string(forKey: Self.customPathKey), !custom.isEmpty {
            candidates.append(custom)
        }
        candidates.append(Self.bundledCLI.path)
        candidates += [
            "\(home)/.local/bin/filee",
            "\(home)/Applications/Filee.app/Contents/MacOS/filee-cli",
            "/Applications/Filee.app/Contents/MacOS/filee-cli",
            "/opt/homebrew/bin/filee",
            "/usr/local/bin/filee",
        ]
        for path in candidates where fm.isExecutableFile(atPath: path) {
            let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
            if fm.isExecutableFile(atPath: url.path) {
                executableURL = url
                return url
            }
        }
        executableURL = nil
        return nil
    }

    static var bundledCLI: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/engine/filee-cli")
    }

    var isBundled: Bool {
        guard let executableURL else { return false }
        return executableURL.path.hasPrefix(Bundle.main.bundleURL.resolvingSymlinksInPath().path)
    }

    static func cliURL(fromUserChoice url: URL) -> URL {
        if url.pathExtension.lowercased() == "app" {
            let embedded = url.appendingPathComponent("Contents/MacOS/engine/filee-cli")
            if FileManager.default.isExecutableFile(atPath: embedded.path) { return embedded }
            return url.appendingPathComponent("Contents/MacOS/filee-cli")
        }
        return url
    }

    struct RunResult {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    func run(_ arguments: [String]) throws -> RunResult {
        guard let executable = executableURL ?? locate() else { throw FileeError.notFound }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = Self.scratchDirectory
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        try process.run()

        let errBox = DataBox()
        let errHandle = err.fileHandleForReading
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            errBox.data = errHandle.readDataToEndOfFile()
            group.leave()
        }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()
        return RunResult(status: process.terminationStatus,
                         stdout: String(decoding: outData, as: UTF8.self),
                         stderr: String(decoding: errBox.data, as: UTF8.self))
    }

    func loadFormats() throws {
        let versionResult = try run(["version"])
        if versionResult.status == 0 {
            version = versionResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let result = try run(["formats"])
        guard result.status == 0 else {
            throw FileeError.failed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let parsed = Self.parseFormatList(result.stdout)
        guard !parsed.isEmpty else { throw FileeError.failed(L("error.noFormats")) }
        var map: [String: FormatInfo] = [Self.folderId: FormatInfo(id: Self.folderId, displayName: L("format.folder"),
                                                                   category: "Archive", extensions: [], writable: true)]
        var extensions: [String: String] = [:]
        for format in parsed {
            map[format.id] = format
            for ext in format.extensions where extensions[ext] == nil {
                extensions[ext] = format.id
            }
        }
        lock.lock()
        formats = map
        extensionMap = extensions
        lock.unlock()
    }

    static func parseFormatList(_ text: String) -> [FormatInfo] {
        var category = ""
        var result: [FormatInfo] = []
        for raw in text.components(separatedBy: .newlines) {
            let rawLine = raw.replacingOccurrences(of: "\r", with: "")
            if rawLine.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            if !rawLine.hasPrefix(" ") {
                if rawLine.hasSuffix(":") { category = String(rawLine.dropLast()) }
                continue
            }
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let space = line.firstIndex(of: " ") else { continue }
            let id = String(line[..<space])
            let rest = line[space...].trimmingCharacters(in: .whitespaces)
            guard let separator = rest.range(of: "  .", options: .backwards) else { continue }
            var display = String(rest[..<separator.lowerBound]).trimmingCharacters(in: .whitespaces)
            var writable = true
            let readOnly = " (read only)"
            if display.hasSuffix(readOnly) {
                display = String(display.dropLast(readOnly.count))
                writable = false
            }
            let extensions = rest[separator.upperBound...]
                .components(separatedBy: " .")
                .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                .filter { !$0.isEmpty }
            result.append(FormatInfo(id: id, displayName: display, category: category,
                                     extensions: extensions, writable: writable))
        }
        return result
    }

    func detect(_ url: URL) -> String? {
        let name = url.lastPathComponent.lowercased()
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count > 1 else { return nil }
        lock.lock()
        defer { lock.unlock() }
        for index in 1..<parts.count {
            let ext = parts[index...].joined(separator: ".")
            if let id = extensionMap[ext] { return id }
        }
        return nil
    }

    func targets(for id: String) throws -> TargetSet {
        lock.lock()
        if let cached = targetCache[id] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        let result = try run(["formats", id])
        guard result.status == 0 else {
            throw FileeError.failed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        var set = Self.parseTargets(result.stdout)
        if info(id)?.category == "Archive", id != Self.folderId, !set.now.contains(Self.folderId) {
            set = TargetSet(now: [Self.folderId] + set.now, withEngines: set.withEngines)
        }
        lock.lock()
        targetCache[id] = set
        lock.unlock()
        return set
    }

    static func parseTargets(_ text: String) -> TargetSet {
        var now: [String] = []
        var later: [String] = []
        var inOptional = false
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.replacingOccurrences(of: "\r", with: "")
            if line.hasPrefix("With optional engines") {
                inOptional = true
                continue
            }
            guard line.hasPrefix("  ") else { continue }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("(") { continue }
            let ids = trimmed.components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if inOptional { later += ids } else { now += ids }
        }
        return TargetSet(now: now, withEngines: later)
    }

    func info(_ id: String) -> FormatInfo? {
        lock.lock()
        defer { lock.unlock() }
        return formats[id]
    }
}

enum ItemState {
    case pending, running, done, skipped, failed, cancelled
}

struct LineResult {
    let source: String
    let state: ItemState
    let outputs: [String]
    let message: String?

    static func parse(_ line: String, sources: [String]) -> LineResult? {
        let prefixes: [(String, ItemState)] = [
            ("ok    ", .done), ("skip  ", .skipped), ("stop  ", .cancelled), ("fail  ", .failed),
        ]
        guard let match = prefixes.first(where: { line.hasPrefix($0.0) }) else { return nil }
        let prefix = match.0
        let state = match.1
        let body = String(line.dropFirst(prefix.count))
        guard let source = sources.filter({ body.hasPrefix($0) }).max(by: { $0.count < $1.count }) else {
            return nil
        }
        let rest = String(body.dropFirst(source.count))
        switch state {
        case .done:
            let arrow = " -> "
            let list = rest.hasPrefix(arrow) ? String(rest.dropFirst(arrow.count)) : rest
            return LineResult(source: source, state: .done, outputs: splitOutputs(list), message: nil)
        case .failed:
            let message = rest.hasPrefix(": ") ? String(rest.dropFirst(2)) : rest
            return LineResult(source: source, state: .failed, outputs: [], message: message)
        default:
            return LineResult(source: source, state: state, outputs: [], message: nil)
        }
    }

    static func splitOutputs(_ text: String) -> [String] {
        var parts = text.components(separatedBy: ", /").enumerated().map {
            $0.offset == 0 ? $0.element : "/" + $0.element
        }
        guard var last = parts.last else { return [] }
        let fm = FileManager.default
        while !fm.fileExists(atPath: last), let paren = last.range(of: " (", options: .backwards) {
            last = String(last[..<paren.lowerBound])
        }
        parts[parts.count - 1] = last
        return parts.filter { !$0.isEmpty }
    }
}

final class ConversionRun {
    let process = Process()
    private let sources: [String]
    private var buffer = Data()
    var onLine: ((String) -> Void)?
    var onResult: ((LineResult) -> Void)?
    var onExit: ((Int32, String) -> Void)?

    init(executable: URL, arguments: [String], sources: [String]) {
        self.sources = sources
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = FileeEngine.scratchDirectory
    }

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
            let errBox = DataBox()
            let group = DispatchGroup()
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                errBox.data = errHandle.readDataToEndOfFile()
                group.leave()
            }
            while true {
                let chunk = outHandle.availableData
                if chunk.isEmpty { break }
                DispatchQueue.main.async { self.consume(chunk) }
            }
            group.wait()
            proc.waitUntilExit()
            let status = proc.terminationStatus
            let errText = String(decoding: errBox.data, as: UTF8.self)
            DispatchQueue.main.async {
                self.flush()
                self.onExit?(status, errText)
            }
        }
    }

    func cancel() {
        guard process.isRunning else { return }
        process.interrupt()
    }

    func forceStop() {
        guard process.isRunning else { return }
        process.terminate()
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            handle(String(decoding: lineData, as: UTF8.self))
        }
    }

    private func flush() {
        if !buffer.isEmpty {
            let rest = String(decoding: buffer, as: UTF8.self)
            buffer.removeAll()
            handle(rest)
        }
    }

    private func handle(_ raw: String) {
        let line = raw.replacingOccurrences(of: "\r", with: "")
        guard !line.isEmpty else { return }
        onLine?(line)
        if let result = LineResult.parse(line, sources: sources) {
            onResult?(result)
        }
    }
}
