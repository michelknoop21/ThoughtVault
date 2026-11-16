#if os(macOS)
import AppKit
import SwiftUI
import XCTest
@testable import ThoughtVault

/// The floating panel used to be a fixed 440pt, so an hour-long timer
/// ("1:19:23") was truncated to "1:19:...". The panel now sizes to the widget.
@MainActor
final class RecordingWidgetLayoutTests: XCTestCase {
    func testPanelFitsHourTimerWhilePaused() throws {
        let vm = RecordingViewModel()
        setDuration(5, on: vm)
        vm.recordingState = .paused      // widest badge label: PAUZE
        defer {
            FloatingWidgetController.shared.hide()
            vm.recordingState = .idle
        }

        // Open with a short timer, then let it pass the hour while the panel is up.
        FloatingWidgetController.shared.show(recordingVM: vm)
        let panel = try XCTUnwrap(NSApp.windows.first { $0 is NSPanel && $0.level == .floating })
        let startWidth = panel.frame.width
        setDuration(4763, on: vm)        // 1:19:23
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        panel.contentView?.layoutSubtreeIfNeeded()

        let needed = NSHostingView(rootView: RecordingWidgetView().fixedSize().environment(vm)).fittingSize
        XCTAssertGreaterThan(panel.frame.width, startWidth, "panel did not grow with the timer")

        // fittingSize rounds a lone hosting view up to whole points (451.4 -> 452),
        // the panel measures the same widget unrounded, hence the 1pt allowance.
        XCTAssertGreaterThanOrEqual(panel.frame.width + 1, needed.width + 32, "panel cuts off the widget")

        if let view = panel.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("widget-1h.png")
            try rep.representation(using: .png, properties: [:])?.write(to: url)
            print("WIDGET_SHOT=\(url.path) panel=\(panel.frame.width) needed=\(needed.width)")
        }
    }

    private func setDuration(_ seconds: TimeInterval, on vm: RecordingViewModel) {
        vm.audioRecorder.duration = seconds
        vm.systemAudioCapture.duration = seconds
    }
}
#endif
