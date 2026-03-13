// FloatingWidgetController.swift
// TranscriptStudio
// nl.prezent.TranscriptStudio
//
// Manages the floating NSPanel overlay that shows recording status on macOS.
// The panel sits above all other windows so users can monitor recording
// while working in video call apps or other tools.

#if os(macOS)
import AppKit
import SwiftUI

@MainActor
class FloatingWidgetController {

    // MARK: - Shared Instance

    static let shared = FloatingWidgetController()

    // MARK: - Private State

    private var floatingWindow: NSPanel?

    private init() {}

    // MARK: - Public API

    /// Shows the floating recording widget anchored near the bottom-right corner
    /// of the main screen. Does nothing if the panel is already visible.
    func show(recordingVM: RecordingViewModel) {
        guard floatingWindow == nil else { return }

        let hostingView = NSHostingView(
            rootView: RecordingWidgetView()
                .environment(recordingVM)
        )
        hostingView.layer?.backgroundColor = .clear

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 60),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true

        updatePosition(for: panel)

        panel.orderFront(nil)
        floatingWindow = panel

        // Reposition when the screen configuration changes.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    /// Hides and releases the floating panel.
    func hide() {
        floatingWindow?.close()
        floatingWindow = nil
        NotificationCenter.default.removeObserver(
            self,
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    /// Repositions the panel to the bottom-right corner of the main screen.
    /// Call this after display configuration changes or when the panel needs
    /// to be snapped back to its default position.
    func updatePosition() {
        guard let panel = floatingWindow else { return }
        updatePosition(for: panel)
    }

    // MARK: - Private Helpers

    private func updatePosition(for panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let margin: CGFloat = 20
        let x = screen.visibleFrame.maxX - panel.frame.width - margin
        let y = screen.visibleFrame.minY + margin
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    @objc private func screenParametersDidChange() {
        updatePosition()
    }
}
#endif
