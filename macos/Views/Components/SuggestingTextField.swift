// SuggestingTextField.swift
// ThoughtVault
// com.buildmind.ThoughtVault
//
// TextField with a chevron menu of known values (roles, organizations,
// expertise) so recurring values are picked instead of retyped. In append
// mode a picked value is added comma-separated to the existing text.

import SwiftUI

struct SuggestingTextField: View {

    let placeholder: String
    @Binding var text: String
    let suggestions: [String]
    /// false: picking replaces the text. true: picking appends ", value".
    var appendMode: Bool = false

    var body: some View {
        HStack(spacing: TS.Spacing.xs) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .font(TS.Font.body)
                .autocorrectionDisabled()

            if !suggestions.isEmpty {
                Menu {
                    ForEach(suggestions, id: \.self) { value in
                        Button(value) { apply(value) }
                    }
                } label: {
                    Image(systemName: "chevron.down.circle")
                        .font(TS.Font.body)
                        .foregroundStyle(Color.labelSecondary)
                        .frame(minWidth: 28, minHeight: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .fixedSize()
                .accessibilityLabel("Kies uit bestaande waarden")
            }
        }
    }

    private func apply(_ value: String) {
        guard appendMode else {
            text = value
            return
        }
        let existing = text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !existing.contains(value) else { return }
        text = (existing + [value]).joined(separator: ", ")
    }
}
