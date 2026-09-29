// TasksView+iOS.swift
// ThoughtVault
//
// iOS Taken, reconstructed from the approved NorthStar
// (docs/design/ios/thoughtvault-ios-taken-northstar.jpg): title, the
// Actief / Wachtrij / Voltooid switch and task cards with status pill,
// progress and step. The NorthStar's "Alle taken / Mijn taken" filter and
// per-task retry have no existing behaviour and are left out; a running
// task opens its Verwerken detail, delete stays in the context menu.

#if os(iOS)
import SwiftUI

enum IOSTaskFilter: Hashable {
    case active, queued, done

    func matches(_ status: TaskStatus) -> Bool {
        switch self {
        case .active: return status != .completed && status != .pending && status != .queued
        case .queued: return status == .pending || status == .queued
        case .done: return status == .completed
        }
    }
}

extension TasksView {

    private var iosTasks: [TranscriptTask] {
        if ProcessingMode.isLocalMode { return recordingVM.activeTasks }
        let fetchedIDs = Set(tasksVM.activeTasks.map(\.taskId))
        return tasksVM.activeTasks + recordingVM.activeTasks.filter { !fetchedIDs.contains($0.taskId) }
    }

    var iosBody: some View {
        IOSTasksScreen(tasks: iosTasks,
                       isLoading: tasksVM.isLoading,
                       error: tasksVM.errorMessage,
                       onDismissError: { tasksVM.errorMessage = nil },
                       onRefresh: {
                           if !ProcessingMode.isLocalMode { await tasksVM.loadActiveTasks() }
                       },
                       onCancel: { taskToCancel = $0 },
                       onDelete: { taskToDelete = $0 })
    }
}

private struct IOSTasksScreen: View {
    let tasks: [TranscriptTask]
    let isLoading: Bool
    let error: String?
    let onDismissError: () -> Void
    let onRefresh: () async -> Void
    let onCancel: (TranscriptTask) -> Void
    let onDelete: (TranscriptTask) -> Void

    @State private var filter: IOSTaskFilter = .active
    @State private var debugTaskID: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                IOSBrandBar()
                    .padding(.top, -10)
                ZStack(alignment: .topTrailing) {
                    IOSNightIllustration()
                        .frame(width: 200, height: 100)
                        .opacity(0.45)
                        .offset(x: IOSMetric.gutter, y: -6)
                    IOSScreenTitle(title: "Taken",
                                   subtitle: "Verwerking en inzicht uit je opnames en notities, stap voor stap.")
                        .padding(.trailing, 90)
                }
                .padding(.top, 10)
                IOSSegmented(options: [(IOSTaskFilter.active, "Actief", nil),
                                       (.queued, "Wachtrij", nil),
                                       (.done, "Voltooid", nil)],
                             selection: $filter, height: 42)
                    .padding(.top, 14)
                if let error {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(IOSColor.danger)
                        Text(error).font(.system(size: 13)).foregroundStyle(IOSColor.text2).lineLimit(2)
                        Spacer()
                        Button { onDismissError() } label: { Image(systemName: "xmark").foregroundStyle(IOSColor.text2) }
                            .accessibilityLabel("Melding sluiten")
                    }
                    .padding(14)
                    .iosCard()
                    .padding(.top, 14)
                }
                list
                    .padding(.top, 16)
            }
            .padding(.horizontal, IOSMetric.gutter)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .refreshable { await onRefresh() }
        .iosScreen()
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $debugTaskID) { IOSProcessingView(taskID: $0) }
        .task(id: tasks.count) {
            if IOSDebug.open == "processing", debugTaskID == nil, let first = tasks.first(where: { $0.status.isActive }) {
                debugTaskID = first.taskId
            }
        }
    }

    @ViewBuilder
    private var list: some View {
        let shown = tasks.filter { filter.matches($0.status) }
        if isLoading && tasks.isEmpty {
            ProgressView().tint(IOSColor.lavender).frame(maxWidth: .infinity).padding(40)
        } else if shown.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "checklist")
                    .font(.system(size: 30))
                    .foregroundStyle(IOSColor.iconViolet)
                Text(emptyTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(IOSColor.text)
                Text(filter == .done
                     ? "Afgeronde verwerkingen staan direct in Notulen."
                     : "Wanneer je een opname start of een audiobestand importeert, verschijnt de voortgang hier.")
                    .font(.system(size: 13))
                    .foregroundStyle(IOSColor.text2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(28)
            .iosCard()
        } else {
            VStack(spacing: 14) {
                ForEach(shown) { task in
                    if task.status.isActive {
                        NavigationLink { IOSProcessingView(taskID: task.taskId) } label: { card(task) }
                            .buttonStyle(.plain)
                            .contextMenu { menu(task) }
                    } else {
                        card(task).contextMenu { menu(task) }
                    }
                }
            }
        }
    }

    private var emptyTitle: String {
        switch filter {
        case .active: return "Geen actieve taken"
        case .queued: return "Niets in de wachtrij"
        case .done: return "Nog niets voltooid"
        }
    }

    @ViewBuilder
    private func menu(_ task: TranscriptTask) -> some View {
        if task.status.isActive {
            Button("Annuleren", systemImage: "xmark.circle") { onCancel(task) }
        }
        Button("Verwijderen", systemImage: "trash", role: .destructive) { onDelete(task) }
    }

    private func card(_ task: TranscriptTask) -> some View {
        let showsBar = task.status.isActive
        return HStack(alignment: .top, spacing: 16) {
            IOSIconTile(systemName: icon(task.status), tint: tint(task.status), size: 44)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    Text(task.filename)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(IOSColor.text)
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    IOSStatusPill(status: task.status)
                }
                Text(meta(task))
                    .font(.system(size: 12.5))
                    .foregroundStyle(IOSColor.text2)
                if showsBar {
                    HStack(spacing: 12) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color(red: 0.16, green: 0.17, blue: 0.30))
                                Capsule().fill(IOSColor.accentGradient)
                                    .frame(width: geo.size.width * max(0, min(1, task.displayProgress)))
                            }
                        }
                        .frame(height: 6)
                        if task.status != .pending && task.status != .queued {
                            Text("\(Int((task.displayProgress * 100).rounded()))%")
                                .font(.system(size: 13).monospacedDigit())
                                .foregroundStyle(IOSColor.text)
                        }
                    }
                    .padding(.top, 4)
                    .accessibilityHidden(true)
                }
                Text(detail(task))
                    .font(.system(size: 12))
                    .foregroundStyle(task.status == .error ? IOSColor.danger : IOSColor.text2)
                    .lineLimit(2)
            }
            if task.status.isActive {
                IOSChevron().padding(.top, 34)
            }
        }
        .padding(16)
        .iosCard(raised: task.status.isActive)
        .contentShape(Rectangle())
    }

    private func meta(_ task: TranscriptTask) -> String {
        ["Opname", task.createdAt.map { IOSFormat.day($0) }].compactMap { $0 }.joined(separator: "  \u{00B7}  ")
    }

    private func detail(_ task: TranscriptTask) -> String {
        switch task.status {
        case .error: return task.errorMessage ?? "Verwerking is mislukt."
        case .completed: return "Notities en samenvatting gereed."
        case .pending, .queued: return "Wacht op verwerking\u{2026}"
        default: return task.status.displayName + "\u{2026}"
        }
    }

    private func icon(_ status: TaskStatus) -> String {
        switch status {
        case .completed: return "mic"
        case .error: return "doc.text"
        case .pending, .queued: return "doc.text.fill"
        default: return "waveform"
        }
    }

    private func tint(_ status: TaskStatus) -> IOSIconTile.Tint {
        switch status {
        case .completed: return .green
        case .pending, .queued: return .blue
        default: return .violet
        }
    }
}
#endif
