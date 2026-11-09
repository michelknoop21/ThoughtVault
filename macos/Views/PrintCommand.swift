import SwiftUI

#if os(macOS)
import AppKit
import WebKit

/// Print action published by the transcript detail view for the menu command.
struct PrintActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var printAction: (() -> Void)? {
        get { self[PrintActionKey.self] }
        set { self[PrintActionKey.self] = newValue }
    }
}

/// Replaces the default Print item with a "Afdrukken…" item (⌘P) bound to the focused notule.
struct PrintCommands: Commands {
    @FocusedValue(\.printAction) private var printAction

    var body: some Commands {
        CommandGroup(replacing: .printItem) {
            Button("Afdrukken…") { printAction?() }
                .keyboardShortcut("p")
                .disabled(printAction == nil)
        }
    }
}

enum NotulePrinter {
    /// Renders the HTML offscreen and opens the print panel (A4). Shared by PDF export and ⌘P.
    @MainActor
    static func print(html: String, keepAlive: @escaping (WKWebView?) -> Void) {
        let printInfo = NSPrintInfo.shared
        printInfo.paperSize = NSSize(width: 595, height: 842)
        printInfo.topMargin = 36
        printInfo.bottomMargin = 36
        printInfo.leftMargin = 54
        printInfo.rightMargin = 54

        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 595, height: 842))
        keepAlive(webView)
        webView.loadHTMLString(html, baseURL: nil)

        // Brief delay for WKWebView to finish rendering before printing
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            let op = webView.printOperation(with: printInfo)
            op.showsPrintPanel = true
            op.showsProgressPanel = true
            op.run()
            keepAlive(nil)
        }
    }
}
#endif
