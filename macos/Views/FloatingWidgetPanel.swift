// FloatingWidgetPanel.swift
// ThoughtVault
// com.buildmind.ThoughtVault
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
    private weak var observedRecordingVM: RecordingViewModel?

    private init() {}

    // MARK: - Public API

    /// Shows the floating recording widget anchored near the bottom-right corner
    /// of the main screen. Does nothing if the panel is already visible.
    func show(recordingVM: RecordingViewModel) {
        guard floatingWindow == nil else { return }

        let hostingView = NSHostingView(
            rootView: RecordingWidgetView()
                .padding(16) // Room for shadows outside the capsule
                .environment(recordingVM)
        )
        // Ensure the hosting view has a transparent layer so the capsule
        // shape is the only visible element (no rectangular corners).
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false

        updatePosition(for: panel)

        panel.orderFront(nil)
        floatingWindow = panel

        // Observe state changes directly so the widget hides even when
        // the main SwiftUI window is minimised or hidden.
        observedRecordingVM = recordingVM
        observeRecordingState()

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
        observedRecordingVM = nil
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
        // The panel is oversized (16pt padding on each side) to give shadows room.
        // Offset the margin so the visible capsule lands 20pt from the screen edge.
        let shadowPadding: CGFloat = 16
        let margin: CGFloat = 20 - shadowPadding
        let x = screen.visibleFrame.maxX - panel.frame.width - margin
        let y = screen.visibleFrame.minY + margin
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    @objc private func screenParametersDidChange() {
        updatePosition()
    }

    /// Watches `recordingState` via Observation (not SwiftUI) so changes are
    /// detected even when the main window is minimised or hidden.
    private func observeRecordingState() {
        guard let vm = observedRecordingVM else { return }

        withObservationTracking {
            _ = vm.recordingState
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, let vm = self.observedRecordingVM else { return }
                switch vm.recordingState {
                case .idle, .error:
                    self.hide()
                default:
                    self.observeRecordingState()
                }
            }
        }
    }
}
#endif
