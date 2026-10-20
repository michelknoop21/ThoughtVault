// ProfilesView+iOS.swift
// ThoughtVault
//
// iOS Profielen, reconstructed from the approved NorthStar
// (docs/design/ios/thoughtvault-ios-profielen-northstar.jpg): the selected
// (default) profile, the other profiles and the edit rows. Selecting a
// profile makes it the default for new recordings ("defaultProfile"). The
// edit rows open the existing profile editor; built-in profiles are read-only.
// The NorthStar's "Premium" badges have no profile-level meaning in the app
// and are left out.

#if os(iOS)
import SwiftUI

extension ProfilesView {

    var iosBody: some View {
        IOSProfilesScreen(profiles: profiles,
                          isLoading: isLoading,
                          errorMessage: errorMessage,
                          onAdd: { showCreateSheet = true },
                          onEdit: { profileToEdit = $0 },
                          onDelete: { profileToDelete = $0; showDeleteConfirm = true })
    }
}

private struct IOSProfilesScreen: View {
    let profiles: [Profile]
    let isLoading: Bool
    let errorMessage: String?
    let onAdd: () -> Void
    let onEdit: (Profile) -> Void
    let onDelete: (Profile) -> Void

    @Environment(RecordingViewModel.self) private var recordingVM
    @AppStorage("defaultProfile") private var defaultProfile = ""

    private var selected: Profile? {
        profiles.first { $0.id == defaultProfile } ?? profiles.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    IOSScreenTitle(title: "Profielen",
                                   subtitle: "Stel in hoe ThoughtVault jouw gesprekken verwerkt en samenvat.")
                    Button(action: onAdd) {
                        HStack(spacing: 10) {
                            Image(systemName: "plus")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(IOSColor.iconViolet)
                                .frame(width: 32, height: 32)
                                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(IOSColor.tile))
                            Text("Profiel\ntoevoegen")
                                .font(.system(size: 12.5))
                                .foregroundStyle(IOSColor.text)
                                .multilineTextAlignment(.leading)
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 58)
                        .iosCard(raised: true)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 6)
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(IOSColor.danger)
                        .padding(.top, 14)
                }

                if isLoading && profiles.isEmpty {
                    ProgressView().tint(IOSColor.lavender).frame(maxWidth: .infinity).padding(40)
                } else if let selected {
                    IOSSectionHeader("Geselecteerd profiel")
                        .padding(.top, 22)
                    selectedCard(selected)
                        .padding(.top, 10)

                    let others = profiles.filter { $0.id != selected.id }
                    if !others.isEmpty {
                        IOSSectionHeader("Overige profielen")
                            .padding(.top, 24)
                        VStack(spacing: 0) {
                            ForEach(Array(others.enumerated()), id: \.element.id) { index, profile in
                                if index > 0 { IOSDivider(inset: 76) }
                                Button { select(profile) } label: { otherRow(profile, index: index) }
                                    .buttonStyle(.plain)
                                    .contextMenu { menu(profile) }
                            }
                        }
                        .iosCard()
                        .padding(.top, 10)
                    }

                    editSection(selected)
                        .padding(.top, 24)
                }
            }
            .padding(.horizontal, IOSMetric.gutter)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .iosScreen()
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Cards

    private func selectedCard(_ profile: Profile) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "doc.plaintext.fill")
                .font(.system(size: 30))
                .foregroundStyle(.white)
                .frame(width: 66, height: 66)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.62, green: 0.36, blue: 1.0), Color(red: 0.42, green: 0.22, blue: 0.85)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)))
                .shadow(color: IOSColor.violet.opacity(0.5), radius: 10)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 8) {
                    Text(profile.name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(IOSColor.text)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if profile.isDefault == true {
                        Text("Standaard")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(IOSColor.lavender)
                            .padding(.horizontal, 10)
                            .frame(height: 24)
                            .background(Capsule().fill(IOSColor.tile))
                    }
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.white, IOSColor.violet)
                        .accessibilityHidden(true)
                }
                if let description = profile.description, !description.isEmpty {
                    Text(description)
                        .font(.system(size: 13))
                        .foregroundStyle(IOSColor.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .background(
            RadialGradient(colors: [Color(red: 0.34, green: 0.20, blue: 0.74).opacity(0.35), .clear],
                           center: UnitPoint(x: 0.2, y: 0.3), startRadius: 0, endRadius: 260)
                .clipShape(RoundedRectangle(cornerRadius: IOSMetric.radius, style: .continuous))
        )
        .iosCard(highlighted: true)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isSelected)
    }

    private func otherRow(_ profile: Profile, index: Int) -> some View {
        let tints: [IOSIconTile.Tint] = [.violet, .blue, .red, .green]
        return HStack(alignment: .center, spacing: 16) {
            IOSIconTile(systemName: symbol(profile), tint: tints[index % tints.count], size: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text(profile.name)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(IOSColor.text)
                if let description = profile.description, !description.isEmpty {
                    Text(description)
                        .font(.system(size: 12))
                        .foregroundStyle(IOSColor.text2)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 6)
            Text("Kies")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(IOSColor.link)
        }
        .padding(12)
        .contentShape(Rectangle())
        .accessibilityHint("Maak dit het standaardprofiel")
    }

    @ViewBuilder
    private func menu(_ profile: Profile) -> some View {
        Button("Kies als standaard", systemImage: "checkmark.circle") { select(profile) }
        if profile.isDefault != true {
            Button("Bewerken", systemImage: "pencil") { onEdit(profile) }
            Button("Verwijderen", systemImage: "trash", role: .destructive) { onDelete(profile) }
        }
    }

    // MARK: Edit

    @ViewBuilder
    private func editSection(_ profile: Profile) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            IOSSectionHeader("Profiel bewerken")
            Text(profile.isDefault == true
                 ? "Standaard profielen kunnen niet worden bewerkt. Maak een eigen profiel om dit aan te passen."
                 : "Pas de instellingen van het geselecteerde profiel aan.")
                .font(.system(size: 13))
                .foregroundStyle(IOSColor.text2)
        }
        if profile.isDefault != true {
            VStack(spacing: 0) {
                editRow("person", "Rol", "Bepaal de rol en het perspectief van de samenvatting.", profile)
                IOSDivider()
                editRow("text.alignleft", "Stijl", "Kies toon en detailniveau.", profile)
                IOSDivider()
                editRow("list.bullet.rectangle", "Secties", "Bepaal welke onderdelen de notule heeft.", profile)
                IOSDivider()
                editRow("gearshape", "Inhoud", "Wat moet er in de notulen staan.", profile)
                IOSDivider()
                Button { onDelete(profile) } label: {
                    IOSRow(icon: "trash", tint: .red, title: "Profiel verwijderen") { EmptyView() }
                }
                .buttonStyle(.plain)
            }
            .iosCard()
            .padding(.top, 10)
        }
    }

    private func editRow(_ icon: String, _ title: String, _ subtitle: String, _ profile: Profile) -> some View {
        Button { onEdit(profile) } label: {
            IOSRow(icon: icon, title: title, subtitle: subtitle) { IOSChevron() }
        }
        .buttonStyle(.plain)
    }

    // MARK: Helpers

    private func select(_ profile: Profile) {
        defaultProfile = profile.id
        if recordingVM.recordingState == .idle,
           let match = recordingVM.availableProfiles.first(where: { $0.id == profile.id }) {
            recordingVM.selectedProfile = match
        }
    }

    private func symbol(_ profile: Profile) -> String {
        switch profile.icon {
        case let icon? where !icon.isEmpty && UIImage(systemName: icon) != nil: return icon
        default: return "doc.text"
        }
    }
}
#endif
