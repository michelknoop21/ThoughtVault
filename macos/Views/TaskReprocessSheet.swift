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
    @State private var retranscribe = false
    @State private var optimizeAudio = false

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
            if RecordingFeatures.enabled {
            Toggle("Opnieuw transcriberen", isOn: $retranscribe)
                .disabled(recordingVM.historyAudioURL(for: entry) == nil)
            if retranscribe {
                Toggle("Audio optimaliseren", isOn: $optimizeAudio)
                Text("Verbetert het volume op een tijdelijke kopie. Herstel van beschadigde spraak is niet gegarandeerd. Het origineel blijft bewaard.")
                    .font(TS.Font.caption).foregroundStyle(Color.labelSecondary)
            }

            }
            Text(hasTranscription && !retranscribe
                 ? "De opgeslagen transcriptie wordt opnieuw tot notule verwerkt. De bestaande notule wordt pas vervangen als de nieuwe versie is goedgekeurd."
                 : "De opname wordt opnieuw getranscribeerd en daarna tot notule verwerkt.")
                .font(TS.Font.caption)
                .foregroundStyle(Color.labelSecondary)
                .fixedSize(horizontal: false, vertical: true)

            ViewThatFits(in: .horizontal) {
            HStack(spacing: TS.Spacing.sm) { actionButtons }
            VStack(alignment: .trailing, spacing: TS.Spacing.sm) { actionButtons }
            }
        }
        .padding(TS.Spacing.lg)
#if os(macOS)
        .frame(idealWidth: 460, maxWidth: 520)
#else
        .presentationDetents([.large])
#endif
        .onAppear {
            title = entry.title
            profileId = profiles.first { $0.id == entry.profileId }?.id ?? recordingVM.selectedProfile?.id ?? profiles.first?.id ?? ""
            let current = SuggestedModels.currentModel(for: provider)
            model = modelChoices.contains(current) ? current : modelChoices.first ?? ""
        }
    }

    @ViewBuilder private var actionButtons: some View {
                Button("Annuleer") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Titel opslaan") {
                    recordingVM.renameHistoryTask(entry, title: title)
                    dismiss()
                }
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Opnieuw verwerken") {
                    recordingVM.reprocessHistoryTask(entry, title: title, profileId: profileId,
                                                     model: modelChoices.isEmpty ? nil : model, retranscribe: retranscribe, optimizeAudio: retranscribe && optimizeAudio)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(Color.brandPrimary)
                .disabled(profileId.isEmpty || !recordingVM.canReprocess(entry))
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
