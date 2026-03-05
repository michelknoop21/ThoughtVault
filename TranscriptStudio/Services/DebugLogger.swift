import Foundation
import OSLog

// MARK: - Log Level

enum LogLevel: Int, Comparable, CustomStringConvertible {
    case debug   = 0
    case info    = 1
    case warning = 2
    case error   = 3

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var description: String {
        switch self {
        case .debug:   return "DEBUG"
        case .info:    return "INFO"
        case .warning: return "WARNING"
        case .error:   return "ERROR"
        }
    }

    var emoji: String {
        switch self {
        case .debug:   return "🔍"
        case .info:    return "ℹ️"
        case .warning: return "⚠️"
        case .error:   return "❌"
        }
    }
}

// MARK: - DebugLogger

/// Application-wide debug logger.
///
/// In DEBUG builds, messages are printed to the Xcode console with level, subsystem, and message.
/// In RELEASE builds, logging is silent — no output is produced and no data is written to disk.
final class DebugLogger: @unchecked Sendable {

    static let shared = DebugLogger()

    /// The minimum log level to emit. Messages below this level are silently dropped.
    /// Defaults to `.debug` in DEBUG builds, `.error` in RELEASE builds.
    var minimumLevel: LogLevel

    private let subsystem = "nl.prezent.TranscriptStudio"
    private let osLogger: Logger

    private init() {
        #if DEBUG
        self.minimumLevel = .debug
        #else
        self.minimumLevel = .error
        #endif
        self.osLogger = Logger(subsystem: "nl.prezent.TranscriptStudio", category: "App")
    }

    // MARK: - Logging Methods

    /// Logs a debug-level message. Only emitted in DEBUG builds.
    func debug(_ message: String, category: String = "General", file: String = #file, line: Int = #line) {
        log(level: .debug, message: message, category: category, file: file, line: line)
    }

    /// Logs an info-level message.
    func info(_ message: String, category: String = "General", file: String = #file, line: Int = #line) {
        log(level: .info, message: message, category: category, file: file, line: line)
    }

    /// Logs a warning-level message.
    func warning(_ message: String, category: String = "General", file: String = #file, line: Int = #line) {
        log(level: .warning, message: message, category: category, file: file, line: line)
    }

    /// Logs an error-level message. Also reported to CrashReporter in release builds.
    func error(_ message: String, category: String = "General", file: String = #file, line: Int = #line) {
        log(level: .error, message: message, category: category, file: file, line: line)
    }

    /// Logs an Error object at error level.
    func error(_ error: Error, context: String? = nil, category: String = "General", file: String = #file, line: Int = #line) {
        let contextPrefix = context.map { "[\($0)] " } ?? ""
        let message = "\(contextPrefix)\(error.localizedDescription)"
        log(level: .error, message: message, category: category, file: file, line: line)
    }

    // MARK: - Core Log

    private func log(level: LogLevel, message: String, category: String, file: String, line: Int) {
        guard level >= minimumLevel else { return }

        #if DEBUG
        let filename = URL(fileURLWithPath: file).lastPathComponent
        let output = "\(level.emoji) [\(level)] [\(category)] \(filename):\(line) — \(message)"
        print(output)
        #else
        // In release: only log errors to the system log via OSLog (no console output)
        if level == .error {
            osLogger.error("\(message, privacy: .public)")
        }
        #endif
    }
}
