// LiveActivityManager.swift
// TranscriptStudio
// nl.prezent.TranscriptStudio
//
// Manages the iOS Live Activity that surfaces recording status on the lock screen
// and in the Dynamic Island. Guards on ActivityKit availability so this file
// compiles cleanly on macOS where ActivityKit is absent.

#if canImport(ActivityKit)
import ActivityKit
import Foundation
import Observation
import OSLog

private let log = Logger(subsystem: "nl.prezent.TranscriptStudio", category: "LiveActivity")

@available(iOS 16.2, *)
@Observable
@MainActor
final class LiveActivityManager {

    // MARK: - Shared Instance

    static let shared = LiveActivityManager()

    // MARK: - State

    /// The currently active Live Activity, if any.
    var currentActivity: Activity<RecordingActivityAttributes>?

    /// Tracks the last update timestamp so we can throttle waveform pushes.
    private var lastUpdateDate: Date = .distantPast

    private init() {}

    // MARK: - Public API

    /// Creates a new Live Activity for the given recording profile.
    ///
    /// Any leftover activity from a previous session is ended first to prevent
    /// orphaned Live Activities (e.g. after an app crash).
    func startActivity(profileName: String) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            log.info("Live Activities not enabled on this device — skipping.")
            return
        }

        // Clean up any orphaned activity before starting a new one.
        if let existing = currentActivity {
            await existing.end(dismissalPolicy: .immediate)
            currentActivity = nil
            log.info("Ended orphaned Live Activity before starting new one.")
        }

        let attributes = RecordingActivityAttributes(profileName: profileName)
        let initialState = RecordingActivityAttributes.ContentState()

        do {
            let activity = try Activity.request(
                attributes: attributes,
                contentState: initialState,
                pushType: nil
            )
            currentActivity = activity
            log.info("Started Live Activity: \(activity.id)")
        } catch {
            log.error("Failed to start Live Activity: \(error.localizedDescription)")
        }
    }

    /// Pushes a waveform update to the active Live Activity.
    ///
    /// Throttled to a maximum of ~4 updates per second (minimum interval 0.23 s)
    /// to balance animation smoothness with system resource usage.
    ///
    /// - Parameters:
    ///   - levels: Raw audio levels array (any length). Condensed to 8 bars internally.
    ///   - duration: Unused directly — the live timer is driven by `startDate` in ContentState.
    ///   - isPaused: Whether recording is currently paused.
    func updateWaveform(levels: [Float], duration: TimeInterval, isPaused: Bool) async {
        guard let activity = currentActivity else { return }

        let now = Date()
        guard now.timeIntervalSince(lastUpdateDate) >= 0.23 else { return }
        lastUpdateDate = now

        let condensed = condenseToEightBars(levels)
        let newState = RecordingActivityAttributes.ContentState(
            startDate: activity.contentState.startDate,
            isPaused: isPaused,
            waveformLevels: isPaused ? Array(repeating: 0.0, count: 8) : condensed
        )

        await activity.update(using: newState)
    }

    /// Ends the current Live Activity and dismisses it immediately.
    func stopActivity() async {
        guard let activity = currentActivity else { return }
        await activity.end(dismissalPolicy: .immediate)
        currentActivity = nil
        log.info("Ended Live Activity.")
    }

    // MARK: - Helpers

    /// Condenses an arbitrary-length audio levels array down to exactly 8 bars
    /// by dividing into 8 equal chunks and taking the maximum value from each.
    func condenseToEightBars(_ levels: [Float]) -> [Float] {
        guard !levels.isEmpty else { return Array(repeating: 0.0, count: 8) }
        if levels.count == 8 { return levels }

        var result = [Float](repeating: 0.0, count: 8)
        let chunkSize = max(1, levels.count / 8)

        for i in 0..<8 {
            let start = i * chunkSize
            let end = min(start + chunkSize, levels.count)
            if start < levels.count {
                result[i] = levels[start..<end].max() ?? 0.0
            }
        }
        return result
    }
}
#endif
