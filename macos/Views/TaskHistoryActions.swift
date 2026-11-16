// TaskHistoryActions.swift
// ThoughtVault
//
// The actions on a task in the Taken history (menu items, reprocess sheet and
// confirmations), shared by the list and the detail sheet on macOS and iOS.

import SwiftUI

enum TaskHistoryAction: Identifiable {
    case reprocess(TaskHistoryEntry)
    case deleteRecording(TaskHistoryEntry)
    case delete(TaskHistoryEntry)

    var entry: TaskHistoryEntry {
        switch self {
        case .reprocess(let entry), .deleteRecording(let entry), .delete(let entry): return entry
        }
    }

    var id: String {
        switch self {
        case .reprocess(let entry): return "reprocess-" + entry.id
        case .deleteRecording(let entry): return "recording-" + entry.id
        case .delete(let entry): return "delete-" + entry.id
        }
    }
}

/// Menu entries for one history task.
struct TaskHistoryMenuItems: View {
    @Environment(RecordingViewModel.self) private var recordingVM
    let entry: TaskHistoryEntry
    @Binding var action: TaskHistoryAction?
    var onDetails: (() -> Void)?
    var onOpenTranscript: ((Transcript) -> Void)?

    var body: some View {
        if let onDetails {
            Button("Details", systemImage: "info.circle", action: onDetails)
        }
        Button("Opnieuw verwerken…", systemImage: "arrow.clockwise") { action = .reprocess(entry) }
            .disabled(!recordingVM.canReprocess(entry))
        if let onOpenTranscript, let record = recordingVM.historyRecord(for: entry) {
            Button("Naar de notule", systemImage: "doc.text") { onOpenTranscript(record.asTranscript) }
        }
        Button("Opname verwijderen…", systemImage: "waveform.slash", role: .destructive) { action = .deleteRecording(entry) }
            .disabled(recordingVM.historyAudioURL(for: entry) == nil)
        Button("Taak verwijderen…", systemImage: "trash", role: .destructive) { action = .delete(entry) }
    }
}

/// Presents the reprocess sheet and the delete confirmations for `action`.
struct TaskHistoryActionsModifier: ViewModifier {
    @Environment(RecordingViewModel.self) private var recordingVM
    @Binding var action: TaskHistoryAction?
    /// Called after the task itself was deleted (the detail sheet closes then).
    var onDeleted: () -> Void = {}

    func body(content: Content) -> some View {
        content
            .sheet(item: reprocessEntry) { entry in
                TaskReprocessSheet(entry: entry)
            }
            .alert("Opname verwijderen", isPresented: isShowing { if case .deleteRecording = $0 { return true }; return false }) {
                Button("Opname verwijderen", role: .destructive) {
                    if let entry = action?.entry { recordingVM.deleteHistoryRecording(entry) }
                    action = nil
                }
                Button("Annuleer", role: .cancel) { action = nil }
            } message: {
                Text("Het audiobestand van \"\(action?.entry.title ?? "")\" wordt definitief verwijderd. De notule en de transcriptie blijven bewaard.")
            }
            .alert("Taak verwijderen", isPresented: isShowing { if case .delete = $0 { return true }; return false }) {
                Button("Alleen taak verwijderen", role: .destructive) { delete(includeNotule: false) }
                if let entry = action?.entry, recordingVM.historyRecord(for: entry) != nil {
                    Button("Taak en notule verwijderen", role: .destructive) { delete(includeNotule: true) }
                }
                Button("Annuleer", role: .cancel) { action = nil }
            } message: {
                Text("\"\(action?.entry.title ?? "")\" verdwijnt uit Taken. Een lopende verwerking stopt. De notule en de opname blijven bewaard, tenzij je kiest voor Taak en notule verwijderen.")
            }
    }

    private func delete(includeNotule: Bool) {
        if let entry = action?.entry { recordingVM.deleteHistoryTask(entry, includeNotule: includeNotule) }
        action = nil
        onDeleted()
    }

    private var reprocessEntry: Binding<TaskHistoryEntry?> {
        Binding(get: { if case .reprocess(let entry) = action { return entry }; return nil },
                set: { if $0 == nil { action = nil } })
    }

    private func isShowing(_ matches: @escaping (TaskHistoryAction) -> Bool) -> Binding<Bool> {
        Binding(get: { action.map(matches) ?? false },
                set: { if !$0, let current = action, matches(current) { action = nil } })
    }
}

extension View {
    func taskHistoryActions(_ action: Binding<TaskHistoryAction?>, onDeleted: @escaping () -> Void = {}) -> some View {
        modifier(TaskHistoryActionsModifier(action: action, onDeleted: onDeleted))
    }
}

enum TaskHistoryFormat {
    private static let nl = Locale(identifier: "nl_NL")

    static func date(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(nl))
    }

    /// "45 s", "4 min 12 s", "1 u 05 min".
    static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total < 60 { return "\(total) s" }
        if total < 3600 { return "\(total / 60) min \(total % 60) s" }
        return String(format: "%d u %02d min", total / 3600, total % 3600 / 60)
    }

    static func outcome(_ entry: TaskHistoryEntry, isRunning: Bool) -> String {
        entry.status.isActive && !isRunning ? "Onderbroken" : entry.outcomeLabel
    }

    /// "<model> · $2 / $10 per mln tokens" for models with a known price.
    static func modelLabel(_ model: String) -> String {
        guard let price = SuggestedModels.price(of: model) else { return model }
        return "\(model) · $\(price.input.formatted()) / $\(price.output.formatted()) per mln tokens"
    }
}
