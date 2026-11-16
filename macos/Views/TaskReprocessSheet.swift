// TaskReprocessSheet.swift
// ThoughtVault
//
// Reprocess a finished or failed task: change the title, pick a profile and,
// for providers with a model choice, one of the suggested models under the price cap.

import SwiftUI

struct TaskReprocessSheet: View {
    @Environment(RecordingViewModel.self) private var recordingVM
    @Environment(\.dismiss) private var dismiss

    let entry: TaskHistoryEntry

    @State private var title = ""
    @State private var profileId = ""
    @State private var model = ""

    private let provider = SuggestedModels.currentProvider

    private var profiles: [Profile] {
        recordingVM.availableProfiles.isEmpty ? Profile.defaults : recordingVM.availableProfiles
    }

    private var modelChoices: [String] {
        guard recordingVM.isLocalMode, SuggestedModels.modelKey(for: provider) != nil else { return [] }
        return SuggestedModels.choices(for: provider, current: SuggestedModels.currentModel(for: provider))
    }

    private var hasTranscription: Bool { recordingVM.historyRecord(for: entry) != nil && recordingVM.isLocalMode }

    var body: some View {
        VStack(alignment: .leading, spacing: TS.Spacing.md) {
            Text("Opnieuw verwerken")
                .font(TS.Font.bodyBold)
                .foregroundStyle(Color.labelPrimary)
                .accessibilityAddTraits(.isHeader)

            field("Titel") {
                TextField("Titel", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
            }
            field("Profiel") {
                Picker("Profiel", selection: $profileId) {
                    ForEach(profiles) { Text($0.name).tag($0.id) }
                }
                .labelsHidden()
            }
            modelField

            Text(hasTranscription
                 ? "De opgeslagen transcriptie wordt opnieuw tot notule verwerkt. De bestaande notule wordt pas vervangen als de nieuwe versie is goedgekeurd."
                 : "De opname wordt opnieuw getranscribeerd en daarna tot notule verwerkt.")
                .font(TS.Font.caption)
                .foregroundStyle(Color.labelSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: TS.Spacing.sm) {
                Button("Annuleer") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Titel opslaan") {
                    recordingVM.renameHistoryTask(entry, title: title)
                    dismiss()
                }
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Opnieuw verwerken") {
                    recordingVM.reprocessHistoryTask(entry, title: title, profileId: profileId,
                                                     model: modelChoices.isEmpty ? nil : model)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(Color.brandPrimary)
                .disabled(profileId.isEmpty || !recordingVM.canReprocess(entry))
            }
        }
        .padding(TS.Spacing.lg)
#if os(macOS)
        .frame(width: 460)
#else
        .presentationDetents([.medium, .large])
#endif
        .onAppear {
            title = entry.title
            profileId = profiles.first { $0.id == entry.profileId }?.id ?? recordingVM.selectedProfile?.id ?? profiles.first?.id ?? ""
            let current = SuggestedModels.currentModel(for: provider)
            model = modelChoices.contains(current) ? current : modelChoices.first ?? ""
        }
    }

    @ViewBuilder
    private var modelField: some View {
        if modelChoices.count > 1 {
            field("Model (\(provider.displayName))") {
                Picker("Model", selection: $model) {
                    ForEach(modelChoices, id: \.self) { Text(TaskHistoryFormat.modelLabel($0)).tag($0) }
                }
                .labelsHidden()
                Text(SuggestedModels.isMetered(provider)
                     ? "Je ziet alleen aanbevolen modellen tot $3 per miljoen invoertokens en $15 per miljoen uitvoertokens. Je keuze wordt ook je standaardmodel bij Instellingen."
                     : "Je keuze wordt ook je standaardmodel bij Instellingen.")
                    .font(TS.Font.caption)
                    .foregroundStyle(Color.labelTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if recordingVM.isLocalMode {
            let current = SuggestedModels.currentModel(for: provider)
            field("Model") {
                Text(current.isEmpty ? provider.displayName : "\(provider.displayName) · \(current)")
                    .font(TS.Font.footnote)
                    .foregroundStyle(Color.labelSecondary)
            }
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: TS.Spacing.xs) {
            Text(label)
                .font(TS.Font.captionSemibold)
                .foregroundStyle(Color.labelSecondary)
            content()
        }
    }
}
