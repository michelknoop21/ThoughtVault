import SwiftUI

#if os(macOS)
import AppKit

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

#endif
