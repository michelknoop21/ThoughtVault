// TaskHistorySection.swift
// ThoughtVault
//
// "Geschiedenis" on the Taken page (macOS and iOS): finished, failed and
// interrupted tasks from the persistent history, each with details and actions.

import SwiftUI

struct TaskHistorySection: View {
    @Environment(RecordingViewModel.self) private var recordingVM

    /// Tasks that are shown in the active list above.
    let shownTaskIds: Set<String>
    var isCompact = false
    var showsHeader = true
    var onOpenTranscript: ((Transcript) -> Void)?

    @State private var detailId: String?
    @State private var action: TaskHistoryAction?

    /// History entries not already shown as an active task.
    static func entries(excluding ids: Set<String>) -> [TaskHistoryEntry] {
        TaskHistoryStore.shared.entries.filter { !ids.contains($0.id) }
    }

    var body: some View {
        let entries = Self.entries(excluding: shownTaskIds)
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: TS.Spacing.sm) {
                if showsHeader {
                    Text("Geschiedenis")
                        .font(TS.Font.footnoteSemibold)
                        .foregroundStyle(Color.labelSecondary)
                        .padding(.top, TS.Spacing.md)
                        .accessibilityAddTraits(.isHeader)
                }
                ForEach(entries) { entry in
                    row(entry)
                }
            }
            .sheet(item: Binding(get: { detailId.map(DetailID.init) }, set: { detailId = $0?.id })) { item in
                TaskHistoryDetailView(entryId: item.id, onOpenTranscript: onOpenTranscript)
            }
            .taskHistoryActions($action)
        }
    }

    private func row(_ entry: TaskHistoryEntry) -> some View {
        let running = recordingVM.isHistoryTaskRunning(entry)
        return HStack(alignment: .top, spacing: TS.Spacing.sm) {
            Button { detailId = entry.id } label: {
                HStack(alignment: .top, spacing: TS.Spacing.sm) {
                    Image(systemName: icon(entry, running: running))
                        .font(.system(size: 16))
                        .foregroundStyle(tint(entry, running: running))
                        .frame(width: 24, height: 24)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.title)
                            .font(TS.Font.footnoteSemibold)
                            .foregroundStyle(Color.labelPrimary)
                            .lineLimit(isCompact ? 2 : 1)
                        Text(meta(entry))
                            .font(TS.Font.caption)
                            .foregroundStyle(Color.labelTertiary)
                            .lineLimit(2)
                        if entry.status == .error, !entry.isCancelled, let error = entry.errorMessage {
                            Text(error)
                                .font(TS.Font.caption)
                                .foregroundStyle(Color.statusError)
                                .lineLimit(2)
                        }
                    }
                    Spacer(minLength: TS.Spacing.xs)
                    StatusBadge(status: entry.status, label: TaskHistoryFormat.outcome(entry, isRunning: running))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Toont de details van deze taak")

            Menu {
                TaskHistoryMenuItems(entry: entry, action: $action,
                                     onDetails: { detailId = entry.id }, onOpenTranscript: onOpenTranscript)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.labelSecondary)
                    .frame(width: 28, height: 28)
            }
#if os(macOS)
            .menuStyle(.borderlessButton)
#endif
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Acties voor \(entry.title)")
        }
        .padding(TS.Spacing.md)
#if os(iOS)
        .iosCard()
#else
        .modernCard()
#endif
        .contextMenu {
            TaskHistoryMenuItems(entry: entry, action: $action,
                                 onDetails: { detailId = entry.id }, onOpenTranscript: onOpenTranscript)
        }
    }

    private func meta(_ entry: TaskHistoryEntry) -> String {
        [TaskHistoryFormat.date(entry.createdAt),
         entry.profileName,
         entry.recordingSeconds.map { "opname " + TaskHistoryFormat.duration($0) },
         entry.recordingDeleted ? "opname verwijderd" : nil]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private func icon(_ entry: TaskHistoryEntry, running: Bool) -> String {
        if entry.isCancelled { return "xmark.circle.fill" }
        switch entry.status {
        case .completed: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        default: return running ? "waveform" : "pause.circle.fill"
        }
    }

    private func tint(_ entry: TaskHistoryEntry, running: Bool) -> Color {
        if entry.isCancelled { return Color.labelTertiary }
        switch entry.status {
        case .completed: return Color.statusSuccess
        case .error: return Color.statusError
        default: return running ? Color.brandSecondary : Color.statusWarning
        }
    }
}

private struct DetailID: Identifiable { let id: String }
