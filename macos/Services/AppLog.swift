import CryptoKit
import Foundation
import os
#if os(macOS)
import AppKit
#endif

// MARK: - Redaction

/// Masks personal data (e-mail addresses, file paths, media file names) before it reaches the log file.
enum LogRedact {
    /// Stable short token: "k-" plus the first 6 hex characters of SHA256.
    static func mask(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return "k-" + digest.map { String(format: "%02x", $0) }.joined().prefix(6)
    }

    private static let patterns: [NSRegularExpression] = [
        // Unquoted paths may contain spaces: redact through the next hard delimiter to avoid leaking a suffix.
        #"(?:file://|~|(?<![\w.:/]))/(?:[^\r\n/"',]+/)+[^\r\n/"',]*"#,
        #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#,
        #"[^\s"',:()][^"',:()\r\n]*?\.(?:m4a|wav|caf|mp3|mp4|mov|m4v|aac|aiff)\b"#,
    ].enumerated().map { index, pattern in
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: pattern, options: index == 2 ? [.caseInsensitive] : [])
    }

    static func scrub(_ text: String) -> String {
        var result = text
        for regex in patterns {
            let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
            for match in matches.reversed() {
                guard let range = Range(match.range, in: result) else { continue }
                result.replaceSubrange(range, with: mask(String(result[range])))
            }
        }
        return result
    }

    /// Clear-text error kind that is safe to log: type and case name, or NSError domain and code (plus the
    /// underlying error's domain and code), never a message or an associated string value.
    static func describe(_ error: Error) -> String {
        if error is CancellationError || (error as? URLError)?.code == .cancelled { return "cancelled" }
        // A URLError passed as `any Error` reports its dynamic type as NSError; name it explicitly.
        let type = error is URLError ? "URLError" : identifier(String(describing: Swift.type(of: error)))
        if let coded = error as? LogCoded {
            let underlying = coded.logUnderlying.map { " underlying=" + domainAndCode($0 as NSError) } ?? ""
            return "\(type).\(identifier(coded.logCode))" + underlying
        }
        let ns = error as NSError
        let underlying = (ns.userInfo[NSUnderlyingErrorKey] as? NSError).map { " underlying=" + domainAndCode($0) } ?? ""
        return "\(type) \(domainAndCode(ns))" + underlying
    }

    private static func domainAndCode(_ error: NSError) -> String {
        "\(identifier(error.domain).replacingOccurrences(of: " ", with: "_")) \(error.code)"
    }

    /// Keeps ASCII identifier characters (and `=`, `-`, space for `logCode` details) so no free text gets through.
    private static func identifier(_ text: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.=- ")
        return String(String.UnicodeScalarView(text.unicodeScalars.map { allowed.contains($0) ? $0 : "_" }).prefix(80))
    }
}

/// An app error that names its case for `LogRedact.describe`: the case name plus only fixed-set details
/// (an HTTP status, a stage), never an associated string.
protocol LogCoded {
    var logCode: String { get }
    /// A wrapped error whose domain and code are logged one level deep.
    var logUnderlying: Error? { get }
}

extension LogCoded {
    var logUnderlying: Error? { nil }
}

// MARK: - File

/// Rotating log file: `thoughtvault.log` plus one previous generation `thoughtvault.1.log`.
actor LogFile {
    static let rotateBytes = 2_621_440
    static let currentName = "thoughtvault.log"
    static let retention: TimeInterval = 7 * 24 * 60 * 60

    private let current: URL
    private let previous: URL
    private var currentSize: Int

    init(directory: URL) {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        current = directory.appending(path: Self.currentName)
        previous = directory.appending(path: "thoughtvault.1.log")
        if let date = (try? fm.attributesOfItem(atPath: previous.path))?[.modificationDate] as? Date,
           Date().timeIntervalSince(date) > Self.retention {
            try? fm.removeItem(at: previous)
        }
        currentSize = ((try? fm.attributesOfItem(atPath: current.path))?[.size] as? Int) ?? 0
    }

    func append(_ line: String) {
        let data = Data(line.utf8)
        let fm = FileManager.default
        if currentSize + data.count > Self.rotateBytes {
            try? fm.removeItem(at: previous)
            try? fm.moveItem(at: current, to: previous)
            currentSize = 0
        }
        if !fm.fileExists(atPath: current.path) {
            guard fm.createFile(atPath: current.path, contents: nil) else { return }
            currentSize = 0
        }
        guard let handle = try? FileHandle(forWritingTo: current) else { return }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            currentSize += data.count
        } catch {
            // Logging must never make the app fail.
        }
    }

    /// Last `maxBytes` bytes of both files; starts at a line boundary when it had to cut.
    func tail(maxBytes: Int) -> String {
        var data = Data()
        for url in [previous, current] {
            if let part = try? Data(contentsOf: url) { data.append(part) }
        }
        guard data.count > maxBytes else { return String(decoding: data, as: UTF8.self) }
        var cut = data.suffix(maxBytes)
        if let newline = cut.firstIndex(of: 0x0A) { cut = cut[cut.index(after: newline)...] }
        return String(decoding: cut, as: UTF8.self)
    }
}

// MARK: - Session marker

enum SessionOutcome: Equatable, Sendable {
    case clean
    case crashed(stage: String?)
}

// MARK: - Logger

/// Category logger: every call goes to os.Logger; all but `debug` also to the scrubbed log file.
struct AppLog: Sendable {
    private let category: String
    private let logger: Logger

    init(category: String) {
        self.category = category
        logger = Logger(subsystem: "com.buildmind.ThoughtVault", category: category)
    }

    func debug(_ message: String) { logger.debug("\(message, privacy: .private)") }
    func info(_ message: String) { write("INFO", message); logger.info("\(message, privacy: .private)") }
    func notice(_ message: String) { info(message) }
    func warning(_ message: String) { write("WARN", message); logger.warning("\(message, privacy: .private)") }
    func error(_ message: String) { write("ERROR", message); logger.error("\(message, privacy: .private)") }
    func fault(_ message: String) { error(message) }

    static let clickPath = AppLog(category: "Klikpad")

    static var directory: URL { AppEnvironment.supportDirectory.appending(path: "Logs", directoryHint: .isDirectory) }
    /// The current log file, for "Toon logbestand".
    static var fileURL: URL { directory.appending(path: LogFile.currentName) }

    private func write(_ level: String, _ message: String) {
        let flat = String(LogRedact.scrub(message).prefix(2_000)).replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
        Sink.shared.send(.line("\(Date().formatted(.iso8601)) \(level) [\(category)] \(flat)\n"))
    }

    // MARK: Sink

    private enum Item: Sendable {
        case line(String)
        case barrier(CheckedContinuation<Void, Never>)
    }

    /// One ordered consumer writing to the log file. Lines still queued in the stream at a hard crash can be lost:
    /// the crash marker (`session.open`) is the primary crash signal, the log tail is context.
    private final class Sink: Sendable {
        static let shared = Sink()
        let file = LogFile(directory: AppLog.directory)
        private let continuation: AsyncStream<Item>.Continuation

        private init() {
            let (stream, continuation) = AsyncStream<Item>.makeStream()
            self.continuation = continuation
            let file = file
            Task.detached(priority: .utility) {
                for await item in stream {
                    switch item {
                    case .line(let line): await file.append(line)
                    case .barrier(let waiter): waiter.resume()
                    }
                }
            }
        }

        func send(_ item: Item) { continuation.yield(item) }
    }

    /// Waits until every line sent so far is written.
    static func flush() async {
        await withCheckedContinuation { Sink.shared.send(.barrier($0)) }
    }

    static func tail(maxBytes: Int = 1_048_576) async -> String {
        await Sink.shared.file.tail(maxBytes: maxBytes)
    }

    /// Messages of the last `limit` "Klikpad" lines, each capped at 80 characters.
    static func clickPath(in log: String, limit: Int = 30) -> [String] {
        let marker = " [Klikpad] "
        let messages = log.split(separator: "\n").compactMap { line -> String? in
            guard let range = line.range(of: marker) else { return nil }
            return String(line[range.upperBound...].prefix(80))
        }
        return Array(messages.suffix(limit))
    }

    // MARK: Crash marker

    private static func marker(in directory: URL) -> URL { directory.appending(path: "session.open") }

    /// The build that owns the marker. Debug builds share the Release container and version, so they get their own
    /// name: a debugger stop is then "another build" for the installed app.
    static var sessionBuild: String {
        #if DEBUG
        DeviceInfo.appVersion + " debug"
        #else
        DeviceInfo.appVersion
        #endif
    }

    /// Only the production app in a Release build reports crashes to support; Debug and the Dev channel keep them local.
    static var reportsCrashes: Bool {
        #if DEBUG
        reportsCrashes(bundleID: Bundle.main.bundleIdentifier, debug: true)
        #else
        reportsCrashes(bundleID: Bundle.main.bundleIdentifier, debug: false)
        #endif
    }

    static func reportsCrashes(bundleID: String?, debug: Bool) -> Bool { !debug && bundleID == "com.buildmind.ThoughtVault" }

    /// The first line of the marker names the build that wrote it (`build=1.0.344 (344)`). A marker from another
    /// build means the app was replaced (installer, update, another build started), not that it crashed, unless it was
    /// stopped during a stage: an installer does not run in the middle of a recording or transcription. A debug owner is
    /// never reported: stopping the debugger mid-recording is routine.
    static func beginSession(in directory: URL = AppLog.directory, build: String = AppLog.sessionBuild) -> SessionOutcome {
        let url = marker(in: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var outcome = SessionOutcome.clean
        if let data = try? Data(contentsOf: url) {
            let (owner, stage) = parseMarker(String(decoding: data, as: UTF8.self))
            if owner == build {
                session.warning("Previous session \(build) ended without a clean exit")
                outcome = .crashed(stage: stage.isEmpty ? nil : stage)
            } else if owner?.hasSuffix(" debug") != true, let active = SupportStage(rawValue: stage), active != .crash {
                session.warning("Previous session \(owner ?? "older build") stopped during \(active.rawValue); replaced by \(build), reported as a crash")
                outcome = .crashed(stage: active.rawValue)
            } else {
                session.info("Previous session \(owner ?? "older build") ended without a clean exit; replaced by \(build), not reported as a crash")
            }
        }
        try? markerData(build: build, stage: nil).write(to: url, options: .atomic)
        return outcome
    }

    static func resumeSession(in directory: URL = AppLog.directory, build: String = AppLog.sessionBuild) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? markerData(build: build, stage: nil).write(to: marker(in: directory), options: .atomic)
    }

    static func setSessionStage(_ stage: String?, in directory: URL = AppLog.directory, build: String = AppLog.sessionBuild) {
        let url = marker(in: directory)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let data = markerData(build: build, stage: stage)
        // Progress callbacks call this many times a second; only a real change is written.
        guard (try? Data(contentsOf: url)) != data else { return }
        // Atomic: a stop halfway through the write must not leave a cut-off build line that reads as another build.
        try? data.write(to: url, options: .atomic)
    }

    private static let session = AppLog(category: "Sessie")

    private static func markerData(build: String, stage: String?) -> Data { Data("build=\(build)\n\(stage ?? "")".utf8) }

    /// A marker without a build line comes from a build before this format.
    private static func parseMarker(_ text: String) -> (owner: String?, stage: String) {
        guard text.hasPrefix("build=") else { return (nil, text) }
        let rest = text.dropFirst("build=".count)
        guard let newline = rest.firstIndex(of: "\n") else { return (String(rest), "") }
        return (String(rest[..<newline]), String(rest[rest.index(after: newline)...]))
    }

    static func endSession(in directory: URL = AppLog.directory) {
        try? FileManager.default.removeItem(at: marker(in: directory))
    }
}

#if os(macOS)
extension AppLog {
    @MainActor private static var terminationObserver: (center: NotificationCenter, token: NSObjectProtocol)?

    @MainActor
    static func endSessionOnTermination(center: NotificationCenter = .default, directory: URL = AppLog.directory) {
        if let observer = terminationObserver { observer.center.removeObserver(observer.token) }
        let token = center.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: nil) { _ in
            AppLog.endSession(in: directory)
        }
        terminationObserver = (center, token)
    }
}
#endif
