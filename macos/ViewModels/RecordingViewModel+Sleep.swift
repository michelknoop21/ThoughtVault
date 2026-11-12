#if os(macOS)
import Foundation
private let log = AppLog(category: "RecordingVM")

extension RecordingViewModel {
    /// Stops the active capture(s) for the selected mode and returns the final audio file.
    /// Combined mode mixes mic and system audio; on fallback `audioMixFallbackOccurred` is set.
    func finishCapturedSession() async -> URL? {
        switch selectedMode {
        case .microphone:
            _ = await systemAudioCapture.stopCapture()
            return await audioRecorder.stopRecording()
        case .systemAudio:
            let result = await systemAudioCapture.stopCapture()
            _ = await audioRecorder.stopRecording()
            return result.systemAudioURL
        case .combined:
            let result = await systemAudioCapture.stopCapture()
            let micURL = await audioRecorder.stopRecording()
            if let sys = result.systemAudioURL, let mic = micURL {
                var offset: TimeInterval = 0
                if let sysStart = systemAudioCapture.startedAt, let micStart = audioRecorder.startedAt {
                    offset = sysStart.timeIntervalSince(micStart)
                }
                let mixed = await mixAudioFiles(micURL: mic, systemURL: sys, systemStartOffset: offset)
                if mixed == mic {
                    audioMixFallbackOccurred = true
                } else {
                    UserDefaults.standard.set(mixed.path, forKey: "combinedAudio_\(mic.lastPathComponent)")
                }
                return mixed
            } else {
                audioMixFallbackOccurred = true
                return result.systemAudioURL ?? micURL
            }
        }
    }

    func handleWillSleep() {
        guard recordingState.isRecording else { return }
        log.info("[RecordingVM] System will sleep — stopping active recording")
        Task {
            await stopLiveTranscription()
            // The mixed file lands in the saved recordings; it is not processed automatically.
            let url = await finishCapturedSession()
            await MainActor.run {
                self.sleepInterruptedFileURL = url
                self.recordingState = .idle
            }
        }
    }

    func handleDidWake() {
        guard sleepInterruptedFileURL != nil else { return }
        log.info("[RecordingVM] System woke — interrupted recording file available for recovery")
        // Load saved recordings so the user can find and reprocess the interrupted file
        loadSavedRecordings()
    }
}
#endif
