// PermissionManager.swift
// TranscriptStudio
// nl.prezent.TranscriptStudio
//
// Checks all required permissions at app startup and surfaces
// missing permissions via observable state so the UI can show a banner.

import AVFoundation
import Foundation
import OSLog
import Speech
#if os(macOS)
import ScreenCaptureKit
#elseif os(iOS)
import UIKit
#endif

private let log = Logger(subsystem: "nl.prezent.TranscriptStudio", category: "Permissions")

@MainActor
@Observable
final class PermissionManager {

    static let shared = PermissionManager()

    // MARK: - Observable State

    var microphoneGranted: Bool = false
    var screenRecordingGranted: Bool = false
    var speechRecognitionGranted: Bool = false

    /// True when the permission was explicitly denied (re-prompting is a no-op;
    /// the user must change it in System Settings).
    var microphoneDenied: Bool = false
    var speechRecognitionDenied: Bool = false

    /// True when any essential permission is missing.
    var hasMissingPermissions: Bool {
        !microphoneGranted || !screenRecordingGranted
    }

    /// Human-readable list of missing permissions for the banner.
    var missingPermissionNames: [String] {
        var names: [String] = []
        if !microphoneGranted { names.append("Microfoon") }
        if !screenRecordingGranted { names.append("Schermopname") }
        if !speechRecognitionGranted { names.append("Spraakherkenning") }
        return names
    }

    /// Set to true while we're actively checking permissions.
    var isChecking: Bool = false

    // MARK: - Init

    private init() {}

    // MARK: - Check All

    /// Checks all permissions without prompting the user.
    /// Call this at app startup to detect revoked permissions.
    func checkAllPermissions() async {
        isChecking = true
        defer { isChecking = false }

        // Microphone
        let audioStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        microphoneGranted = audioStatus == .authorized
        microphoneDenied = audioStatus == .denied || audioStatus == .restricted
        log.info("Microphone permission: \(audioStatus.rawValue) (granted: \(self.microphoneGranted))")

        // Speech recognition
        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        speechRecognitionGranted = speechStatus == .authorized
        speechRecognitionDenied = speechStatus == .denied || speechStatus == .restricted
        log.info("Speech recognition permission: \(speechStatus.rawValue) (granted: \(self.speechRecognitionGranted))")

        // Screen recording (macOS only)
        #if os(macOS)
        await checkScreenRecording()
        #else
        screenRecordingGranted = true // Not applicable on iOS
        #endif

        if hasMissingPermissions {
            log.warning("Missing permissions: \(self.missingPermissionNames.joined(separator: ", "))")
        } else {
            log.info("All permissions granted")
        }
    }

    // MARK: - Individual Permission Requests

    func requestMicrophone() async {
        let audioStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if audioStatus == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            microphoneGranted = granted
        } else if audioStatus == .denied {
            openSystemSettings()
        } else {
            microphoneGranted = audioStatus == .authorized
        }
    }

    func requestSpeechRecognition() async {
        let status = SFSpeechRecognizer.authorizationStatus()
        if status == .notDetermined {
            await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { newStatus in
                    Task { @MainActor in
                        self.speechRecognitionGranted = newStatus == .authorized
                    }
                    continuation.resume()
                }
            }
        } else if status == .denied {
            openSystemSettings()
        } else {
            speechRecognitionGranted = status == .authorized
        }
    }

    #if os(macOS)
    func requestScreenRecording() async {
        // CGRequestScreenCaptureAccess opens System Settings for the user
        CGRequestScreenCaptureAccess()

        // Poll briefly — the user needs time to toggle the switch
        for _ in 0..<5 {
            try? await Task.sleep(for: .seconds(1))
            await checkScreenRecording()
            if screenRecordingGranted { break }
        }
    }

    private func checkScreenRecording() async {
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            screenRecordingGranted = true
        } catch {
            screenRecordingGranted = false
        }
        log.info("Screen recording permission: \(self.screenRecordingGranted)")
    }
    #endif

    // MARK: - System Settings

    func openSystemSettings() {
        #if os(macOS)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
        #else
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #endif
    }

    func openScreenRecordingSettings() {
        #if os(macOS)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }
}
