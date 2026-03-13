// RecordingActivityAttributes.swift
// TranscriptStudio
// nl.prezent.TranscriptStudio
//
// Live Activity data model shared between the main app target and the
// RecordingActivityWidget extension target. Guards on ActivityKit availability
// so the model compiles cleanly on macOS where ActivityKit is absent.

#if canImport(ActivityKit)
import ActivityKit
import Foundation

/// ActivityAttributes that define the Live Activity shown on the iOS lock screen
/// and in the Dynamic Island during an active recording session.
///
/// - Static attributes (set once at activity creation): `profileName`
/// - Dynamic state (updated in real time): `ContentState`
struct RecordingActivityAttributes: ActivityAttributes {

    // MARK: - Static Attributes

    /// The recording profile name displayed in the widget (e.g. "Meeting", "Interview").
    let profileName: String

    // MARK: - Dynamic Content State

    /// Mutable state that drives Live Activity UI updates during recording.
    public struct ContentState: Codable, Hashable {

        /// The timestamp when recording started. Used with SwiftUI's `.timer` text style
        /// to display a live elapsed-time counter without requiring per-second updates.
        var startDate: Date

        /// Whether recording is currently paused. When `true` the waveform
        /// is zeroed out and a pause indicator is shown instead.
        var isPaused: Bool

        /// Eight Float values in the range 0.0–1.0 representing the amplitude
        /// of each waveform bar. Updated approximately 4 times per second
        /// by `LiveActivityManager.updateWaveform(levels:duration:isPaused:)`.
        var waveformLevels: [Float] // 8 values, 0.0–1.0

        init(
            startDate: Date = .now,
            isPaused: Bool = false,
            waveformLevels: [Float] = Array(repeating: 0.3, count: 8)
        ) {
            self.startDate = startDate
            self.isPaused = isPaused
            self.waveformLevels = waveformLevels
        }
    }
}
#endif
