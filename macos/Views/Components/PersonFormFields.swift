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
    @Namespace private var statusThumb

    private static let commaHint = "Meerdere waarden, gescheiden door komma's"

    var body: some View {
        Group {
            SettingFieldRow("Naam") {
                TextField("Naam", text: $naam)
                    .personFieldStyle()
                    .autocorrectionDisabled()
            }

            SettingFieldRow("Rol / Functie") {
                SuggestingTextField(placeholder: "Rol / Functie", text: $rol, suggestions: roleSuggestions)
            }

            SettingFieldRow("Organisatie") {
                SuggestingTextField(placeholder: "Organisatie", text: $organisatie, suggestions: organizationSuggestions)
            }

            SettingFieldRow(aliasLabel, hint: Self.commaHint) {
                #if os(macOS)
                CommaChipsField(text: $aliassen, placeholder: "Voornaam, bijnaam, initialen")
                #else
                TextField("Voornaam, bijnaam, initialen", text: $aliassen)
                    .textFieldStyle(.roundedBorder)
                    .font(TS.Font.body)
                    .autocorrectionDisabled()
                #endif
            }

            if let meetingTypes {
                SettingFieldRow("Typische vergadertypen", hint: Self.commaHint) {
                    TextField("Wekelijks overleg, Klantgesprek", text: meetingTypes)
                        .personFieldStyle()
                        .autocorrectionDisabled()
                }
            }

            SettingFieldRow("Expertise / onderwerpen", hint: Self.commaHint) {
                #if os(macOS)
                CommaChipsField(text: $expertise, placeholder: "grafisch ontwerp, marketing, IT",
                                suggestions: expertiseSuggestions)
                #else
                SuggestingTextField(
                    placeholder: "grafisch ontwerp, marketing, IT",
                    text: $expertise,
                    suggestions: expertiseSuggestions,
                    appendMode: true
                )
                #endif
            }

            if let internalStatus {
                SettingFieldRow("Intern / extern") {
                    #if os(macOS)
                    HStack(spacing: 2) {
                        ForEach(InternalStatus.allCases, id: \.self) { status in
                            StudioSegmentButton(title: LocalizedStringKey(status.label), badge: 0,
                                                selected: internalStatus.wrappedValue == status, thumb: statusThumb) {
                                withAnimation(TS.Animation.quick) { internalStatus.wrappedValue = status }
                            }
                        }
                    }
                    .padding(3)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(HomeColor.side))
                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(HomeColor.sideBorder, lineWidth: 1))
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(Text("Intern / extern"))
                    #else
                    Picker("", selection: internalStatus) {
                        ForEach(InternalStatus.allCases, id: \.self) { status in
                            Text(status.label).tag(status)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 220)
                    #endif
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

extension View {
    /// Dark field on macOS (restyled windows), the rounded system field on iOS.
    @ViewBuilder
    func personFieldStyle() -> some View {
        #if os(macOS)
        studioField()
        #else
        textFieldStyle(.roundedBorder).font(TS.Font.body)
        #endif
    }
}

#if os(macOS)
// MARK: - CommaChipsField

/// A comma-separated value shown as removable chips plus a field to add one
/// (Enter or a comma adds it). The binding stays the same comma-separated
/// text, including what is still being typed, so saving never loses input.
struct CommaChipsField: View {
    @Binding var text: String
    let placeholder: String
    var suggestions: [String] = []

    @State private var items: [String] = []
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(items, id: \.self) { item in
                HStack(spacing: 6) {
                    Text(item).lineLimit(1)
                    Button { remove(item) } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8.5, weight: .bold))
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(Color.white.opacity(0.10)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Verwijder \(item)")
                }
                .font(.system(size: 13.5))
                .foregroundStyle(HomeColor.lavender)
                .padding(.leading, 11)
                .padding(.trailing, 5)
                .frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.brandPrimary.opacity(0.18)))
            }
            HStack(spacing: 4) {
                TextField("", text: $draft, prompt: Text(placeholder).foregroundStyle(HomeColor.text3))
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundStyle(HomeColor.text)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .onSubmit(commitDraft)
                    .frame(minWidth: 150)
                if !suggestions.isEmpty {
                    Menu {
                        ForEach(suggestions.filter { s in !items.contains { $0.caseInsensitiveCompare(s) == .orderedSame } }, id: \.self) { value in
                            Button(value) { add(value) }
                        }
                    } label: {
                        Image(systemName: "chevron.down.circle")
                            .foregroundStyle(HomeColor.text2)
                            .frame(minWidth: 24, minHeight: 24)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .accessibilityLabel("Kies uit bestaande waarden")
                }
            }
            .frame(height: 28)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(HomeColor.field.opacity(0.75)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(focused ? Color.brandSecondary : HomeColor.fieldBorder, lineWidth: focused ? 1.5 : 1))
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        .animation(TS.Animation.quick, value: focused)
        .onAppear(perform: parse)
        .onChange(of: text) { _, _ in if text != composed { parse() } }
        .onChange(of: draft) { _, value in
            if value.contains(",") { commitDraft() } else { text = composed }
        }
    }

    private static func split(_ value: String) -> [String] {
        var seen = Set<String>()
        return value.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    private var composed: String {
        (items + Self.split(draft)).joined(separator: ", ")
    }

    private func parse() {
        items = Self.split(text)
        draft = ""
    }

    private func add(_ value: String) {
        for item in Self.split(value) where !items.contains(where: { $0.caseInsensitiveCompare(item) == .orderedSame }) {
            items.append(item)
        }
        text = composed
    }

    private func commitDraft() {
        let value = draft
        draft = ""
        add(value)
    }

    private func remove(_ item: String) {
        items.removeAll { $0 == item }
        text = composed
    }
}

/// Wrapping row layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map { $0.width }.max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                let width = min(size.width, bounds.width)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                                      proposal: ProposedViewSize(width: width, height: size.height))
                x += width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > width && !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width = row.indices.isEmpty ? min(size.width, width) : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
#endif
