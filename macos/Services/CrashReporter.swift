import Foundation
import OSLog

private let logger = Logger(subsystem: "com.buildmind.ThoughtVault", category: "CrashReporter")

// MARK: - CrashReporter

/// Minimal crash reporting stub. Ready to be wired up to a real crash reporting SDK.
///
/// In DEBUG builds, recorded errors are printed to the console.
/// In RELEASE builds, this is a no-op until a real crash reporting SDK (e.g. Sentry, Crashlytics)
/// is integrated via `configure()`.
final class CrashReporter: @unchecked Sendable {

    static let shared = CrashReporter()

    private var isConfigured = false

    private init() {}

    // MARK: - Configuration

    /// Configures the crash reporter. Call once at app startup from the App entry point.
    ///
    /// Replace the body of this method with the real SDK initialization when integrating
    /// a crash reporting provider (e.g. `SentrySDK.start { ... }`).
    func configure() {
        guard !isConfigured else { return }
        isConfigured = true

        #if DEBUG
        logger.debug("CrashReporter: configured (DEBUG stub — no real crash reporting)")
        #else
        // Integrate a crash reporting SDK (e.g. Sentry) here when ready.
        logger.info("CrashReporter: configured")
        #endif
    }

    // MARK: - Error Recording

    /// Records a non-fatal error with optional context information.
    ///
    /// - Parameters:
    ///   - error: The error to record.
    ///   - context: Optional description of where/why the error occurred.
    func recordError(_ error: Error, context: String? = nil) {
        let contextString = context ?? "unspecified"

        #if DEBUG
        logger.error("CrashReporter: [non-fatal] \(error.localizedDescription) (context: \(contextString))")
        #else
        // Forward to crash reporting SDK here when integrated.
        logger.error("CrashReporter: non-fatal error recorded — \(error.localizedDescription, privacy: .public)")
        #endif
    }

    /// Records a non-fatal error message (without an Error object).
    ///
    /// - Parameters:
    ///   - message: A descriptive error message.
    ///   - context: Optional description of where/why the error occurred.
    func recordMessage(_ message: String, context: String? = nil) {
        let contextString = context ?? "unspecified"

        #if DEBUG
        logger.error("CrashReporter: [message] \(message) (context: \(contextString))")
        #else
        // Forward to crash reporting SDK here when integrated.
        logger.error("CrashReporter: message recorded — \(message, privacy: .public)")
        #endif
    }

    // MARK: - User Context

    /// Sets user identification for crash reports (e.g. after login).
    /// - Parameter userId: An opaque, non-personally-identifiable user identifier.
    func setUserIdentifier(_ userId: String) {
        #if DEBUG
        logger.debug("CrashReporter: user identifier set — \(userId)")
        #else
        // Set user context on crash reporting SDK here when integrated.
        #endif
    }

    /// Clears user identification from crash reports (e.g. on logout).
    func clearUserIdentifier() {
        #if DEBUG
        logger.debug("CrashReporter: user identifier cleared")
        #else
        // Clear user context on crash reporting SDK here when integrated.
        #endif
    }
}
