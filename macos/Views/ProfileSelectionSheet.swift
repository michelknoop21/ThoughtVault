// ProfileSelectionSheet.swift
// ThoughtVault
//
// Profile choice for regenerating a notule or retranscribing a recording. With a local `record`
// (regenerate only) the sheet selects a profile, shows the detail level picker and confirms with
// a button; otherwise a tap on a profile starts right away.

import SwiftUI

struct ProfileSelectionSheet: View {

    @Environment(RecordingViewModel.self) var recordingVM
    @Environment(\.dismiss) private var dismiss

    let mode: TranscriptDetailView.ProfileSheetMode
    /// The local record being regenerated; nil hides the detail level (cloud records, retranscribe).
    var record: TranscriptRecord? = nil
    /// Profile, premium toggle, and the chosen detail level (nil: the profile has no level or none was offered).
    let onSelect: (Profile, Bool, NotuleDetailLevel?) -> Void

    @State private var usePremium = false
    @State private var selectedId: String?
    @State private var level: NotuleDetailLevel = .volledig

    private var displayProfiles: [Profile] {
        recordingVM.availableProfiles.isEmpty
            ? Profile.defaults
            : recordingVM.availableProfiles
    }

    private var selected: Profile? { displayProfiles.first { $0.id == selectedId } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(displayProfiles) { profile in
                        Button {
                            if record != nil { select(profile) } else { onSelect(profile, usePremium, nil) }
                        } label: {
                            HStack(spacing: TS.Spacing.sm) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(profile.name)
                                        .font(TS.Font.bodyMedium)
                                        .foregroundStyle(Color.labelPrimary)
                                    if let prompt = profile.description ?? profile.notulePrompt, !prompt.isEmpty {
                                        Text(prompt)
                                            .font(TS.Font.caption)
                                            .foregroundStyle(Color.labelSecondary)
                                            .lineLimit(2)
                                    }
                                }
                                Spacer(minLength: 0)
                                if record != nil && profile.id == selectedId {
                                    Image(systemName: "checkmark")
                                        .font(TS.Font.bodySemibold)
                                        .foregroundStyle(Color.brandPrimary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Kies een profiel")
                }

                if record != nil, selected?.detailLevel != nil {
                    Section {
                        DetailLevelPicker(level: $level)
                    } header: {
                        Text("Detailniveau")
                    }
                }

                Section {
                    Toggle(isOn: $usePremium) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Premium model")
                                .font(TS.Font.bodyMedium)
                                .foregroundStyle(Color.labelPrimary)
                            Text("Claude: betere kwaliteit, langzamer")
                                .font(TS.Font.caption)
                                .foregroundStyle(Color.labelSecondary)
                        }
                    }
                    .tint(Color.brandPrimary)
                }
            }
            .navigationTitle(
                mode == .regenerate
                ? "Notule regenereren"
                : "Hertranscriberen"
            )
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuleren") { dismiss() }
                }
                if record != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Genereer") {
                            if let selected { onSelect(selected, usePremium, selected.detailLevel != nil ? level : nil) }
                        }
                        .disabled(selected == nil)
                    }
                }
            }
            .task {
                if recordingVM.availableProfiles.isEmpty {
                    await recordingVM.reloadProfiles()
                }
                if let record, selectedId == nil {
                    select(displayProfiles.first { $0.id == record.profileId } ?? displayProfiles[0])
                }
            }
        }
        #if os(macOS)
        .frame(width: 520, height: 640)
        #endif
    }

    /// Selects `profile` and preselects its level by the regenerate rule (DEC-073).
    private func select(_ profile: Profile) {
        selectedId = profile.id
        level = RecordingViewModel.regenerateDetailLevel(record, profile: profile)
    }
}
