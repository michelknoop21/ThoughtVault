// TaskHistoryDetailView.swift
// ThoughtVault
//
// Details of one task from the Taken history: times, steps, engines, outcome,
// whether the recording and the notule still exist, plus the task actions.

import SwiftUI

struct TaskHistoryDetailView: View {
    @Environment(RecordingViewModel.self) private var recordingVM
    @Environment(\.dismiss) private var dismiss

    let entryId: String
    var onOpenTranscript: ((Transcript) -> Void)?

    @State private var action: TaskHistoryAction?

    var body: some View {
        Group {
            if let entry = TaskHistoryStore.shared.entry(entryId) {
                content(entry)
            } else {
                Text("Deze taak bestaat niet meer.").padding(TS.Spacing.lg)
            }
        }
#if os(macOS)
        .frame(minWidth: 460, idealWidth: 560, minHeight: 420, idealHeight: 620)
#endif
        .taskHistoryActions($action, onDeleted: { dismiss() })
    }

    private func content(_ entry: TaskHistoryEntry) -> some View {
        let running = recordingVM.isHistoryTaskRunning(entry)
        let record = recordingVM.historyRecord(for: entry)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: TS.Spacing.sm) {
                VStack(alignment: .leading, spacing: TS.Spacing.xs) {
                    Text(entry.title)
                        .font(TS.Font.bodyBold)
                        .foregroundStyle(Color.labelPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    StatusBadge(status: entry.status, label: TaskHistoryFormat.outcome(entry, isRunning: running))
                }
                Spacer(minLength: TS.Spacing.sm)
                Button("Sluiten") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(TS.Spacing.lg)

            ScrollView {
                VStack(alignment: .leading, spacing: TS.Spacing.md) {
                    if let error = entry.errorMessage, entry.status == .error {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(TS.Font.footnote)
                            .foregroundStyle(Color.statusError)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    detailsGrid(entry, hasRecord: record != nil)
                    stepsList(entry)
                }
                .padding(.horizontal, TS.Spacing.lg)
                .padding(.bottom, TS.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            actionBar(entry, record: record)
                .padding(TS.Spacing.lg)
        }
    }

    private func detailsGrid(_ entry: TaskHistoryEntry, hasRecord: Bool) -> some View {
        let audioPresent = recordingVM.historyAudioURL(for: entry) != nil
        let rows: [(String, String)] = [
            ("Profiel", entry.profileName ?? entry.profileId ?? "Onbekend"),
            ("Gestart", TaskHistoryFormat.date(entry.createdAt)),
            ("Klaar", entry.finishedAt.map(TaskHistoryFormat.date) ?? "Nog niet"),
            ("Verwerkingstijd", entry.totalDuration.map(TaskHistoryFormat.duration) ?? "Onbekend"),
            ("Lengte opname", entry.recordingSeconds.map(TaskHistoryFormat.duration) ?? "Onbekend"),
            ("Transcriptie", entry.transcriptionEngine ?? "Onbekend"),
            ("Notule", [entry.notuleProvider, entry.notuleModel].compactMap { $0 }.joined(separator: " · ").nonEmpty ?? "Onbekend"),
            ("Bestand", entry.filename.isEmpty ? "Onbekend" : entry.filename),
            ("Opname", audioPresent ? "Aanwezig" : (entry.recordingDeleted ? "Verwijderd" : "Niet gevonden")),
            ("Notule opgeslagen", hasRecord ? "Ja" : "Nee"),
        ]
        return Grid(alignment: .leading, horizontalSpacing: TS.Spacing.md, verticalSpacing: TS.Spacing.sm) {
            ForEach(rows, id: \.0) { label, value in
                GridRow {
                    Text(label)
                        .font(TS.Font.caption)
                        .foregroundStyle(Color.labelTertiary)
                    Text(value)
                        .font(TS.Font.footnote)
                        .foregroundStyle(Color.labelPrimary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private func stepsList(_ entry: TaskHistoryEntry) -> some View {
        if !entry.steps.isEmpty {
            VStack(alignment: .leading, spacing: TS.Spacing.xs) {
                Text("Stappen")
                    .font(TS.Font.captionSemibold)
                    .foregroundStyle(Color.labelSecondary)
                ForEach(Array(entry.steps.enumerated()), id: \.offset) { _, step in
                    HStack {
                        Text(step.label)
                            .font(TS.Font.footnote)
                            .foregroundStyle(Color.labelPrimary)
                        Spacer()
                        Text(step.duration.map(TaskHistoryFormat.duration) ?? "loopt")
                            .font(TS.Font.footnote.monospacedDigit())
                            .foregroundStyle(Color.labelSecondary)
                    }
                }
            }
        }
    }

    private func actionBar(_ entry: TaskHistoryEntry, record: TranscriptRecord?) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: TS.Spacing.sm) { actionButtons(entry, record: record) }
            VStack(alignment: .leading, spacing: TS.Spacing.sm) { actionButtons(entry, record: record) }
        }
    }

    @ViewBuilder
    private func actionButtons(_ entry: TaskHistoryEntry, record: TranscriptRecord?) -> some View {
        Button("Opnieuw verwerken…", systemImage: "arrow.clockwise") { action = .reprocess(entry) }
            .buttonStyle(.borderedProminent)
            .tint(Color.brandPrimary)
            .disabled(!recordingVM.canReprocess(entry))
        if let record, let onOpenTranscript {
            Button("Naar de notule", systemImage: "doc.text") {
                dismiss()
                onOpenTranscript(record.asTranscript)
            }
        }
        Button("Opname verwijderen…", systemImage: "waveform.slash", role: .destructive) { action = .deleteRecording(entry) }
            .disabled(recordingVM.historyAudioURL(for: entry) == nil)
        Button("Taak verwijderen…", systemImage: "trash", role: .destructive) { action = .delete(entry) }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
