// PeopleDirectoryView+Mac.swift
// ThoughtVault
//
// macOS layout of Mensen: a header with the count, search and the add button,
// and the people as rows in one card on a readable width (initials, role and
// organisation, expertise tags, the Intern/Extern chip and icon buttons).
// Below 760 pt the expertise moves under the name. iOS keeps the List layout.

#if os(macOS)
import SwiftUI

extension PeopleDirectoryView {

    var macBody: some View {
        GeometryReader { geo in
            let compact = geo.size.width < 760
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 22) {
                    peopleHeader(compact: compact)
                    if isLoading {
                        loadingView
                    } else if let error = loadError {
                        errorView(message: error)
                    } else if people.isEmpty {
                        emptyStateView
                    } else {
                        peopleCard(compact: compact)
                    }
                }
                .frame(maxWidth: 1100, alignment: .leading)
                .padding(.horizontal, compact ? 20 : 34)
                .padding(.top, 18)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .modifier(HiddenWindowTitle())
    }

    // MARK: Header

    private func peopleHeader(compact: Bool) -> some View {
        let title = VStack(alignment: .leading, spacing: 4) {
            Text("Mensen")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(HomeColor.text)
                .accessibilityAddTraits(.isHeader)
            Text("\(countText). ThoughtVault gebruikt deze lijst om namen goed te schrijven en actiepunten toe te wijzen.")
                .font(.system(size: 14))
                .foregroundStyle(HomeColor.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
        let actions = HStack(spacing: 12) {
            TextField("", text: $searchText, prompt: Text("Zoeken...").foregroundStyle(HomeColor.text3))
                .padding(.leading, 20)
                .studioField()
                .overlay(alignment: .leading) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13))
                        .foregroundStyle(HomeColor.text3)
                        .padding(.leading, 12)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: compact ? .infinity : 280)
                .accessibilityLabel(Text("Zoeken"))
            Button("Persoon toevoegen") { showAddSheet = true }
                .buttonStyle(PrimaryButtonStyle())
                .help("Persoon toevoegen")
        }
        return Group {
            if compact {
                VStack(alignment: .leading, spacing: 16) { title; actions }
            } else {
                HStack(alignment: .center, spacing: 16) {
                    title
                    Spacer(minLength: 16)
                    actions
                }
            }
        }
    }

    private var countText: String {
        people.count == 1 ? String(localized: "1 persoon") : String(localized: "\(people.count) personen")
    }

    // MARK: Card

    private func peopleCard(compact: Bool) -> some View {
        VStack(spacing: 0) {
            if !compact {
                HStack(spacing: 16) {
                    Color.clear.frame(width: 44, height: 1)
                    Text("Naam").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Expertise").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Soort").frame(width: 84, alignment: .leading)
                    Color.clear.frame(width: 76, height: 1)
                }
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(HomeColor.text3)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .accessibilityHidden(true)
            }
            if !searchText.isEmpty && filteredPeople.isEmpty {
                Divider().overlay(HomeColor.divider)
                noSearchResultsView
            }
            ForEach(Array(filteredPeople.enumerated()), id: \.element.id) { index, person in
                if index > 0 || !compact { Divider().overlay(HomeColor.divider) }
                personCardRow(person, compact: compact)
            }
        }
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(HomeColor.card.opacity(0.85)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(HomeColor.cardBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func personCardRow(_ person: PersonProfile, compact: Bool) -> some View {
        let subtitle = [person.role, person.organization].filter { !$0.isEmpty }.joined(separator: " · ")
        return HStack(alignment: compact ? .top : .center, spacing: 16) {
            PersonInitials(name: person.name, color: kindColor(person.isInternal), size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(person.name.isEmpty ? "Naamloos" : person.name)
                    .font(.system(size: 15.5, weight: .semibold))
                    .foregroundStyle(HomeColor.text)
                    .lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 13.5))
                        .foregroundStyle(HomeColor.text2)
                        .lineLimit(1)
                }
                if compact {
                    expertiseTags(person.expertiseTags).padding(.top, 6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !compact {
                expertiseTags(person.expertiseTags).frame(maxWidth: .infinity, alignment: .leading)
            }
            StudioChip(text: kindText(person.isInternal), color: kindColor(person.isInternal))
                .frame(width: compact ? nil : 84, alignment: .leading)
            HStack(spacing: 8) {
                iconButton("pencil", tint: HomeColor.text2, label: "Bewerk \(person.name)") { personToEdit = person }
                iconButton("trash", tint: Color.statusError, label: "Verwijder \(person.name)") {
                    personToDelete = person
                    showDeleteConfirmation = true
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private func expertiseTags(_ tags: [String]) -> some View {
        if tags.isEmpty {
            Text("Nog geen expertise")
                .font(.system(size: 13))
                .foregroundStyle(HomeColor.text3)
        } else {
            // Show as many tags as fit on one line, the rest as "+n".
            ViewThatFits(in: .horizontal) {
                ForEach((1...max(1, min(tags.count, 4))).reversed(), id: \.self) { shown in
                    HStack(spacing: 6) {
                        ForEach(tags.prefix(shown), id: \.self) { tag(Text($0)) }
                        if tags.count > shown { tag(Text("+\(tags.count - shown)")) }
                    }
                    .fixedSize()
                }
                tag(Text("+\(tags.count)"))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(tags.joined(separator: ", ")))
        }
    }

    private func tag(_ text: Text) -> some View {
        text
            .font(.system(size: 12))
            .foregroundStyle(HomeColor.text2)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(0.06)))
    }

    private func iconButton(_ icon: String, tint: Color, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13.5))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
        }
        .buttonStyle(StudioIconButtonStyle())
        .accessibilityLabel(label)
        .help(label)
    }

    private func kindColor(_ isInternal: Bool?) -> Color {
        switch isInternal {
        case true:  return HomeColor.ready
        case false: return HomeColor.lavender
        case nil:   return HomeColor.text3
        }
    }

    private func kindText(_ isInternal: Bool?) -> String {
        switch isInternal {
        case true:  return "Intern"
        case false: return "Extern"
        case nil:   return "Onbekend"
        }
    }
}

/// Initials in a tinted circle; also used in the person sheet header.
struct PersonInitials: View {
    let name: String
    let color: Color
    var size: CGFloat = 44

    var body: some View {
        let letters = name.split(separator: " ").filter { $0.first?.isUppercase == true }
        let initials = (letters.count >= 2 ? [letters.first!, letters.last!] : Array(name.split(separator: " ").prefix(2)))
            .compactMap(\.first).map(String.init).joined().uppercased()
        Text(initials.isEmpty ? "?" : initials)
            .font(.system(size: size * 0.34, weight: .bold, design: .rounded))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(Circle().fill(color.opacity(0.2)))
            .accessibilityHidden(true)
    }
}

/// Square icon button: quiet fill, lighter on hover, pressed scale.
struct StudioIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        IconBody(configuration: configuration)
    }

    private struct IconBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var hovered = false

        var body: some View {
            configuration.label
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white.opacity(hovered ? 0.12 : 0.06)))
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
                .onHover { hovered = $0 }
                .animation(TS.Animation.quick, value: configuration.isPressed)
                .animation(TS.Animation.quick, value: hovered)
        }
    }
}
#endif
