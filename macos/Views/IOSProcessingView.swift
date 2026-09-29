// IOSProcessingView.swift
// ThoughtVault
//
// iOS "Verwerken" detail, reconstructed from the approved NorthStar
// (docs/design/ios/thoughtvault-ios-verwerken-northstar.jpg). Opened from a
// "Wordt verwerkt" card; shows the task's real status as steps, cancel, and
// the other tasks still waiting. The NorthStar's audio player is left out:
// the app has no playback.

#if os(iOS)
import SwiftUI

struct IOSProcessingView: View {
    let taskID: String

    @Environment(RecordingViewModel.self) private var recordingVM
    @Environment(TasksViewModel.self) private var tasksVM
    @Environment(\.dismiss) private var dismiss
    @State private var confirmCancel = false
    /// Failed tasks leave the list after a few seconds; remember the last
    /// status so the screen does not then claim success.
    @State private var lastStatus: TaskStatus?

    private var allTasks: [TranscriptTask] {
        if ProcessingMode.isLocalMode { return recordingVM.activeTasks }
        let fetchedIDs = Set(tasksVM.activeTasks.map(\.taskId))
        return tasksVM.activeTasks + recordingVM.activeTasks.filter { !fetchedIDs.contains($0.taskId) }
    }

    private var task: TranscriptTask? { allTasks.first { $0.taskId == taskID } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                IOSScreenTitle(title: "Verwerken",
                               subtitle: "Je opname wordt omgezet naar inzichten en samenvattingen met AI.")
                if let task {
                    currentCard(task)
                        .padding(.top, 20)
                } else if lastStatus == .error {
                    failedCard
                        .padding(.top, 20)
                } else {
                    finishedCard
                        .padding(.top, 20)
                }
                queueSection
            }
            .padding(.horizontal, IOSMetric.gutter)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .iosScreen()
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: task?.status, initial: true) { _, status in
            if let status { lastStatus = status }
        }
        .confirmationDialog("Verwerking annuleren?", isPresented: $confirmCancel, titleVisibility: .visible) {
            Button("Annuleer verwerking", role: .destructive) { cancel() }
            Button("Terug", role: .cancel) {}
        }
    }

    // MARK: Current

    private func currentCard(_ task: TranscriptTask) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    IOSKicker(text: "Huidige opname")
                    Text(task.filename)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(IOSColor.text)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    if let created = task.createdAt {
                        Text(IOSFormat.day(created))
                            .font(.system(size: 15))
                            .foregroundStyle(IOSColor.text2)
                    }
                }
                Spacer(minLength: 0)
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [Color(red: 0.35, green: 0.20, blue: 0.75).opacity(0.35), .clear],
                                             center: .center, startRadius: 30, endRadius: 80))
                        .frame(width: 140, height: 140)
                    IOSProgressRing(progress: task.displayProgress, size: 108, lineWidth: 8, showLabel: false)
                    VStack(spacing: 2) {
                        Text("\(Int((task.displayProgress * 100).rounded()))%")
                            .font(.system(size: 26, weight: .bold).monospacedDigit())
                            .foregroundStyle(IOSColor.text)
                        Text(task.status == .error ? "Mislukt" :
                             (task.status == .queued || task.status == .pending ? "In wachtrij" : "Verwerken\u{2026}"))
                            .font(.system(size: 12))
                            .foregroundStyle(IOSColor.text2)
                    }
                }
                .frame(width: 126, height: 126)
            }

            if task.status == .error {
                Label(task.errorMessage ?? "Verwerking is mislukt.", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(IOSColor.danger)
                    .padding(.top, 16)
            }

            steps(for: task)
                .padding(.top, 18)

            if task.status.isActive {
                Rectangle().fill(IOSColor.divider).frame(height: 1).padding(.top, 16)
                Button { confirmCancel = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(IOSColor.control))
                        Text("Annuleren").font(.system(size: 14.5))
                    }
                    .foregroundStyle(IOSColor.text)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(IOSColor.control.opacity(0.6)))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(IOSColor.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(.top, 16)
            }
        }
        .padding(18)
        .background(
            RadialGradient(colors: [Color(red: 0.30, green: 0.18, blue: 0.68).opacity(0.3), .clear],
                           center: UnitPoint(x: 0.8, y: 0.1), startRadius: 0, endRadius: 260)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        )
        .iosCard(raised: true)
    }

    private var finishedCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Verwerking afgerond", systemImage: "checkmark.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(IOSColor.ready)
            Text("Deze opname wordt niet meer verwerkt. Het resultaat staat in Notulen.")
                .font(.system(size: 14))
                .foregroundStyle(IOSColor.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .iosCard()
    }

    private var failedCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Verwerking mislukt", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(IOSColor.danger)
            Text("De opname staat bij Opgeslagen opnames op het Opnemen-scherm; daar kun je hem opnieuw verwerken.")
                .font(.system(size: 14))
                .foregroundStyle(IOSColor.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .iosCard()
    }

    // MARK: Steps

    private struct Step {
        let title: String
        let detail: String
    }

    /// Local processing has no upload; cloud processing starts with one.
    private var stepList: [Step] {
        var steps = [Step(title: "Transcriptie", detail: "Spraak wordt omgezet naar tekst"),
                     Step(title: "Notulen genereren", detail: "AI maakt notulen en actiepunten\u{2026}"),
                     Step(title: "Notulen opslaan", detail: "Notulen worden opgeslagen in je vault")]
        if !ProcessingMode.isLocalMode {
            steps.insert(Step(title: "Uploaden", detail: "Opname wordt ge\u{00FC}pload"), at: 0)
        }
        return steps
    }

    /// Index of the running step for the task's status.
    private func currentStep(_ status: TaskStatus) -> Int {
        let offset = ProcessingMode.isLocalMode ? 0 : 1
        switch status {
        case .pending, .uploading, .downloading, .converting: return 0
        case .transcribing: return offset
        case .transcribed, .queued, .processingWebhook, .generatingLocal: return offset + 1
        case .completed: return stepList.count
        case .error: return -1
        }
    }

    private func steps(for task: TranscriptTask) -> some View {
        let current = currentStep(task.status)
        let list = stepList
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(list.enumerated()), id: \.offset) { index, step in
                let done = index < current
                let active = index == current && task.status != .queued && task.status != .pending
                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 0) {
                        stepMarker(done: done, active: active)
                        if index < list.count - 1 {
                            Rectangle()
                                .fill(done ? IOSColor.violet : IOSColor.border)
                                .frame(width: 2, height: 16)
                        }
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(step.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(done || active ? IOSColor.text : IOSColor.text3)
                        Text(step.detail)
                            .font(.system(size: 12))
                            .foregroundStyle(done || active ? IOSColor.text2 : IOSColor.text3)
                    }
                    .padding(.top, 2)
                    Spacer(minLength: 0)
                    if active {
                        Text("\(Int((task.displayProgress * 100).rounded()))%")
                            .font(.system(size: 13).monospacedDigit())
                            .foregroundStyle(IOSColor.text2)
                            .padding(.top, 6)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityValue(done ? "Klaar" : active ? "Bezig" : "Nog niet gestart")
            }
        }
    }

    private func stepMarker(done: Bool, active: Bool) -> some View {
        ZStack {
            Circle()
                .fill(done ? Color(red: 0.25, green: 0.16, blue: 0.55) : IOSColor.card)
            Circle()
                .strokeBorder(done || active ? IOSColor.violet : IOSColor.border, lineWidth: 2)
            if done {
                Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
            } else if active {
                Circle().fill(IOSColor.lavender).padding(7)
            }
        }
        .frame(width: 28, height: 28)
        .shadow(color: active ? IOSColor.violet.opacity(0.6) : .clear, radius: 8)
    }

    // MARK: Queue

    @ViewBuilder
    private var queueSection: some View {
        let waiting = allTasks.filter { $0.taskId != taskID && $0.status.isActive }
        if !waiting.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                IOSSectionHeader("Andere verwerkingen (\(waiting.count))")
                VStack(spacing: 0) {
                    ForEach(Array(waiting.enumerated()), id: \.element.id) { index, other in
                        if index > 0 { IOSDivider(inset: 12).padding(.trailing, 12) }
                        NavigationLink {
                            IOSProcessingView(taskID: other.taskId)
                        } label: {
                            queueRow(other)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .iosCard()
            }
            .padding(.top, 26)
        }
    }

    private func queueRow(_ other: TranscriptTask) -> some View {
        HStack(spacing: 14) {
            IOSIconTile(systemName: "doc.text", size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(other.filename)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(IOSColor.text)
                    .lineLimit(1)
                if let created = other.createdAt {
                    Text(IOSFormat.day(created))
                        .font(.system(size: 13))
                        .foregroundStyle(IOSColor.text2)
                }
            }
            Spacer(minLength: 6)
            IOSStatusPill(status: other.status)
            IOSChevron()
        }
        .padding(12)
        .contentShape(Rectangle())
    }

    // MARK: Actions

    private func cancel() {
        guard let task else { return }
        if task.taskId.hasPrefix("local-") {
            recordingVM.cancelLocalProcessing(task.taskId)
        } else {
            Task { await tasksVM.cancelTask(task.taskId) }
        }
        dismiss()
    }
}

/// Status pill used in the queue and the task list.
struct IOSStatusPill: View {
    let status: TaskStatus

    var body: some View {
        HStack(spacing: 7) {
            icon
            Text(label).font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(Capsule().fill(color.opacity(0.12)))
        .overlay(Capsule().strokeBorder(color.opacity(0.35), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private var label: String {
        switch status {
        case .pending, .queued: return "In wachtrij"
        case .completed: return "Voltooid"
        case .error: return "Mislukt"
        default: return "Bezig"
        }
    }

    private var color: Color {
        switch status {
        case .pending, .queued: return IOSColor.warning
        case .completed: return IOSColor.ready
        case .error: return IOSColor.danger
        default: return IOSColor.lavender
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch status {
        case .pending, .queued: Image(systemName: "clock").font(.system(size: 13))
        case .completed: Image(systemName: "checkmark.circle.fill").font(.system(size: 14))
        case .error: Image(systemName: "exclamationmark.triangle").font(.system(size: 13))
        default: ProgressView().controlSize(.mini).tint(color)
        }
    }
}
#endif
