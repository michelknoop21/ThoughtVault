// PersonFormFields.swift
// ThoughtVault
// com.buildmind.ThoughtVault
//
// Shared person form fields used by PersonEditView (directory person) and
// ProfileSettingsView (self profile). Role, organization and expertise offer
// suggestions from existing directory values so recurring values are picked,
// not retyped. Optional bindings switch the caller-specific rows on or off.

import SwiftUI

// MARK: - InternalStatus

/// Maps the tri-state Bool? to a stable Picker-friendly enum.
enum InternalStatus: Int, CaseIterable {
    case intern   = 1
    case extern_  = 0    // rawValue 0 = false
    case onbekend = 2    // rawValue 2 = nil

    var label: String {
        switch self {
        case .intern:   return "Intern"
        case .extern_:  return "Extern"
        case .onbekend: return "Onbekend"
        }
    }

    var boolValue: Bool? {
        switch self {
        case .intern:   return true
        case .extern_:  return false
        case .onbekend: return nil
        }
    }

    static func from(_ value: Bool?) -> InternalStatus {
        switch value {
        case true:  return .intern
        case false: return .extern_
        case nil:   return .onbekend
        }
    }
}

// MARK: - PersonFormFields

struct PersonFormFields: View {

    @Binding var naam: String
    @Binding var rol: String
    @Binding var organisatie: String
    @Binding var aliassen: String
    @Binding var expertise: String
    /// Label above the aliases row (directory person vs self profile wording).
    var aliasLabel: String = "Aliassen"
    /// Self profile only.
    var meetingTypes: Binding<String>? = nil
    /// Directory person only.
    var internalStatus: Binding<InternalStatus>? = nil

    // Suggestion sets from the existing directory, computed once per appearance.
    @State private var roleSuggestions: [String] = []
    @State private var organizationSuggestions: [String] = []
    @State private var expertiseSuggestions: [String] = []

    private static let commaHint = "Meerdere waarden, gescheiden door komma's"

    var body: some View {
        Group {
            SettingFieldRow("Naam") {
                TextField("Naam", text: $naam)
                    .textFieldStyle(.roundedBorder)
                    .font(TS.Font.body)
                    .autocorrectionDisabled()
            }

            SettingFieldRow("Rol / Functie") {
                SuggestingTextField(placeholder: "Rol / Functie", text: $rol, suggestions: roleSuggestions)
            }

            SettingFieldRow("Organisatie") {
                SuggestingTextField(placeholder: "Organisatie", text: $organisatie, suggestions: organizationSuggestions)
            }

            SettingFieldRow(aliasLabel, hint: Self.commaHint) {
                TextField("Michel, Knoop, MK", text: $aliassen)
                    .textFieldStyle(.roundedBorder)
                    .font(TS.Font.body)
                    .autocorrectionDisabled()
            }

            if let meetingTypes {
                SettingFieldRow("Typische vergadertypen", hint: Self.commaHint) {
                    TextField("Wekelijks overleg, Klantgesprek", text: meetingTypes)
                        .textFieldStyle(.roundedBorder)
                        .font(TS.Font.body)
                        .autocorrectionDisabled()
                }
            }

            SettingFieldRow("Expertise / onderwerpen", hint: Self.commaHint) {
                SuggestingTextField(
                    placeholder: "grafisch ontwerp, marketing, IT",
                    text: $expertise,
                    suggestions: expertiseSuggestions,
                    appendMode: true
                )
            }

            if let internalStatus {
                SettingFieldRow("Intern / extern") {
                    Picker("", selection: internalStatus) {
                        ForEach(InternalStatus.allCases, id: \.self) { status in
                            Text(status.label).tag(status)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 220)
                }
            }
        }
        .onAppear { loadSuggestions() }
    }

    private func loadSuggestions() {
        let people = PersonDirectoryService.shared.directoryPeople()
        roleSuggestions = Array(Set(people.map(\.role).filter { !$0.isEmpty })).sorted()
        organizationSuggestions = Array(Set(people.map(\.organization).filter { !$0.isEmpty })).sorted()
        expertiseSuggestions = Array(Set(people.flatMap(\.expertiseTags).filter { !$0.isEmpty })).sorted()
    }
}
