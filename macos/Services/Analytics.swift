import Foundation
import OSLog

private let logger = Logger(subsystem: "com.buildmind.ThoughtVault", category: "Analytics")

// MARK: - Analytics

/// Minimal analytics stub. Ready to be wired up to a real analytics provider if needed.
///
/// In DEBUG builds, events are printed to the console.
/// In RELEASE builds, this is a no-op until a real analytics SDK is integrated.
final class Analytics: Sendable {

    static let shared = Analytics()

    private init() {}

    // MARK: - Event Tracking

    /// Tracks an event with optional properties.
    ///
    /// - Parameters:
    ///   - event: The event name (e.g. "recording_started", "upload_completed").
    ///   - properties: Optional key-value metadata associated with the event.
    func track(_ event: String, properties: [String: Any]? = nil) {
        #if DEBUG
        if let properties = properties, !properties.isEmpty {
            logger.debug("Analytics: \(event) — \(properties.map { "\($0.key)=\($0.value)" }.joined(separator: ", "))")
        } else {
            logger.debug("Analytics: \(event)")
        }
        #endif
        // Integrate analytics SDK here when ready (e.g. TelemetryDeck).
    }

    // MARK: - Convenience Methods

    /// Tracks when a recording session starts.
    func trackRecordingStarted(mode: String) {
        track("recording_started", properties: ["mode": mode])
    }

    /// Tracks when a recording is stopped and uploaded.
    func trackRecordingCompleted(durationSeconds: Double, provider: String) {
        track("recording_completed", properties: [
            "duration_seconds": Int(durationSeconds),
            "provider": provider
        ])
    }

    /// Tracks when a transcription is generated on-device.
    func trackOnDeviceTranscription(characterCount: Int) {
        track("transcription_on_device", properties: ["character_count": characterCount])
    }

    /// Tracks when notulen generation completes.
    func trackNotulenGenerated(provider: String, characterCount: Int) {
        track("notulen_generated", properties: [
            "provider": provider,
            "character_count": characterCount
        ])
    }

    /// Tracks when an upload fails and is queued offline.
    func trackOfflineQueueAdded(reason: String) {
        track("offline_queue_added", properties: ["reason": reason])
    }

    /// Tracks when a queued item is successfully processed.
    func trackOfflineQueueProcessed(retryCount: Int) {
        track("offline_queue_processed", properties: ["retry_count": retryCount])
    }

    /// Tracks an error event.
    func trackError(_ error: Error, context: String) {
        track("error_occurred", properties: [
            "context": context,
            "message": error.localizedDescription
        ])
    }
}
