// ContinuedProcessing.swift
// ThoughtVault
//
// Keeps one local processing run (transcription plus notule) alive when the user leaves the app,
// through an iOS 26 continued processing task. iOS suspends a backgrounded app after about 30 s;
// the task shows the run in the system UI and keeps the process running until it completes.
// Below iOS 26, or when iOS refuses the task, the run tracks as "not covered" and the processing
// screen asks the user to keep the app open.

import Foundation
#if os(iOS)
import BackgroundTasks
#endif

private let log = AppLog(category: "ContinuedTask")

/// Where a local run stands, as shown in the system's progress UI.
enum ContinuedPhase: Equatable, Sendable {
    /// Queued behind another on-device transcription.
    case waiting
    /// Transcription fraction 0...1.
    case transcribing(Double)
    case notule(ModelStep)

    /// Overall fraction for this phase, and the most the heartbeat may add while the phase lasts.
    var band: (fraction: Double, ceiling: Double) {
        func counted(_ step: ModelStep, from: Double, to: Double) -> (Double, Double) {
            let total = Double(max(step.total ?? 0, 1))
            return (from + (to - from) * min(Double(step.index ?? 0), total) / total, to)
        }
        switch self {
        case .waiting: return (0, 0.02)
        case .transcribing(let fraction): return (0.02 + 0.58 * min(max(fraction, 0), 1), 0.6)
        case .notule(let step):
            switch step.kind {
            case .draft, .chunkSummary: return (0.6, 0.75)
            case .sourceCheck: return (0.75, 0.78)
            case .noteCheck: return (0.78, 0.82)
            case .coverage: return counted(step, from: 0.82, to: 0.9)
            case .sentenceCheck: return counted(step, from: 0.9, to: 0.98)
            case .contextSuggestions: return (0.98, 0.99)
            }
        }
    }

    var subtitle: String {
        switch self {
        case .waiting: return String(localized: "continued.waiting")
        case .transcribing(let fraction):
            return String(format: String(localized: "continued.transcribing"), Int((min(max(fraction, 0), 1) * 100).rounded()))
        case .notule(let step): return step.displayLabel
        }
    }
}

/// A running continued processing task; `BGContinuedProcessingTask` on iOS 26+, a fake in tests.
@MainActor
protocol ContinuedTask: AnyObject {
    func report(fraction: Double, subtitle: String)
    func complete(success: Bool)
}

/// Submits continued processing tasks; the system scheduler on iOS 26+, a fake in tests.
@MainActor
protocol ContinuedTaskScheduler {
    /// Registers and submits a task for `id`. `onStart` receives the task once the system runs it;
    /// `onExpire` runs when the system expires it or the user stops it in the system UI.
    func submit(id: String, title: String, subtitle: String,
                onStart: @escaping @MainActor (any ContinuedTask) -> Void,
                onExpire: @escaping @MainActor () -> Void) async throws
}

/// Binds each local processing run to its continued processing task.
@MainActor
@Observable
final class ContinuedProcessing {
    /// nil on macOS, where the app is never suspended for being in the background.
    static let shared: ContinuedProcessing? = {
        #if os(iOS)
        if #available(iOS 26, *) { return ContinuedProcessing(scheduler: SystemContinuedTaskScheduler()) }
        return ContinuedProcessing(scheduler: nil)
        #else
        return nil
        #endif
    }()

    /// Local runs in progress, covered by a task or not.
    private(set) var runIds: Set<String> = []
    /// Runs whose task iOS accepted and has not ended.
    private(set) var coveredRunIds: Set<String> = []
    /// A run is active that nothing keeps alive in the background: the user has to keep the app open.
    var needsAppOpen: Bool { !runIds.isEmpty && coveredRunIds.isEmpty }

    private struct Run {
        var task: (any ContinuedTask)?
        var fraction: Double = 0
        var ceiling: Double = 0.02
        var subtitle: String
        var loggedQuarter = 0
        let onExpire: @MainActor () -> Void
    }

    @ObservationIgnored private let scheduler: (any ContinuedTaskScheduler)?
    @ObservationIgnored private var runs: [String: Run] = [:]
    /// Results of runs that ended before iOS started their (queued) task.
    @ObservationIgnored private var pendingResults: [String: Bool] = [:]
    @ObservationIgnored private var heartbeatTask: Task<Void, Never>?
    /// Seconds between heartbeats; tests drive `heartbeat()` directly.
    @ObservationIgnored var heartbeatInterval: Duration = .seconds(10)

    init(scheduler: (any ContinuedTaskScheduler)?) {
        self.scheduler = scheduler
    }

    /// Starts tracking `runId`, before its work starts so no update or finish is missed.
    /// `onExpire` cancels the run when the task is expired or stopped by the user.
    func track(runId: String, onExpire: @escaping @MainActor () -> Void) {
        runs[runId] = Run(subtitle: ContinuedPhase.transcribing(0).subtitle, onExpire: onExpire)
        runIds.insert(runId)
    }

    /// Asks iOS for a task for a tracked run, while the app is in the foreground.
    func submit(runId: String) async {
        guard let subtitle = runs[runId]?.subtitle else { return }  // already finished
        guard let scheduler else {
            log.info("Continued task not submitted task=\(LogRedact.mask(runId)) reason=unavailable")
            return
        }
        do {
            try await scheduler.submit(
                id: runId, title: String(localized: "continued.title"), subtitle: subtitle,
                onStart: { [weak self] task in self?.started(runId, task) },
                onExpire: { [weak self] in self?.expired(runId) })
            guard runs[runId] != nil else { return }  // finished while submitting; `started` completes it
            coveredRunIds.insert(runId)
            log.info("Continued task submitted task=\(LogRedact.mask(runId)) outcome=accepted")
            startHeartbeat()
        } catch {
            log.info("Continued task submitted task=\(LogRedact.mask(runId)) outcome=refused error=\(LogRedact.describe(error))")
        }
    }

    /// Reports the run's phase; progress never moves backwards.
    func update(runId: String, phase: ContinuedPhase) {
        guard var run = runs[runId] else { return }
        let band = phase.band
        run.fraction = max(run.fraction, band.fraction)
        run.ceiling = max(run.ceiling, band.ceiling, run.fraction)
        run.subtitle = phase.subtitle
        let quarter = min(3, Int(run.fraction * 4))
        if quarter > run.loggedQuarter {
            run.loggedQuarter = quarter
            if run.task != nil { log.info("Continued task progress task=\(LogRedact.mask(runId)) pct=\(quarter * 25)") }
        }
        runs[runId] = run
        run.task?.report(fraction: run.fraction, subtitle: run.subtitle)
    }

    /// Ends the run's task; a task iOS has not started yet completes as soon as it starts.
    func finish(runId: String, success: Bool) {
        guard let run = runs.removeValue(forKey: runId) else { return }
        runIds.remove(runId)
        let wasCovered = coveredRunIds.remove(runId) != nil
        if let task = run.task {
            if success { task.report(fraction: 1, subtitle: run.subtitle) }
            task.complete(success: success)
            log.info("Continued task completed task=\(LogRedact.mask(runId)) success=\(success)")
        } else if wasCovered {
            pendingResults[runId] = success
        }
    }

    private func started(_ runId: String, _ task: any ContinuedTask) {
        guard runs[runId] != nil else {
            // The run ended before iOS started its task: end the task right away.
            let result = pendingResults.removeValue(forKey: runId) ?? false
            task.complete(success: result)
            log.info("Continued task completed task=\(LogRedact.mask(runId)) success=\(result) started_late=true")
            return
        }
        runs[runId]?.task = task
        log.info("Continued task started task=\(LogRedact.mask(runId))")
        if let run = runs[runId] { task.report(fraction: run.fraction, subtitle: run.subtitle) }
    }

    /// The system or the user ended the task early. iOS calls the same handler for both, so the log
    /// cannot tell them apart. The task completes as failed and the run is cancelled.
    private func expired(_ runId: String) {
        pendingResults.removeValue(forKey: runId)
        guard let run = runs.removeValue(forKey: runId) else { return }
        runIds.remove(runId)
        coveredRunIds.remove(runId)
        log.info("Continued task expired task=\(LogRedact.mask(runId)) pct=\(Int((run.fraction * 100).rounded())) cause=system_or_user")
        run.task?.complete(success: false)
        run.onExpire()
    }

    /// Moves every started task a little toward its phase ceiling. A model load or a long draft
    /// request reports nothing for minutes, and iOS expires a task that looks stalled.
    // ponytail: fixed creep of 0.2% per beat, capped at the phase ceiling; replace with streamed
    // token counts if iOS still flags long drafts as stalled.
    func heartbeat() {
        for (id, run) in runs where run.task != nil && run.fraction < run.ceiling {
            let fraction = min(run.ceiling, run.fraction + 0.002)
            runs[id]?.fraction = fraction
            run.task?.report(fraction: fraction, subtitle: run.subtitle)
        }
    }

    private func startHeartbeat() {
        guard heartbeatTask == nil else { return }
        heartbeatTask = Task { [weak self] in
            while let interval = self?.heartbeatInterval, (try? await Task.sleep(for: interval)) != nil {
                guard let self, !self.runs.isEmpty else { break }
                self.heartbeat()
            }
            self?.heartbeatTask = nil
        }
    }
}

#if os(iOS)
/// `BGTaskScheduler` with one wildcard identifier per run (`BGTaskSchedulerPermittedIdentifiers` in Info.plist).
@available(iOS 26, *)
@MainActor
private struct SystemContinuedTaskScheduler: ContinuedTaskScheduler {
    static let identifierPrefix = "com.buildmind.ThoughtVault.processing."

    func submit(id: String, title: String, subtitle: String,
                onStart: @escaping @MainActor (any ContinuedTask) -> Void,
                onExpire: @escaping @MainActor () -> Void) async throws {
        let identifier = Self.identifierPrefix + id
        // Continued processing tasks may register after launch; each identifier only once, hence one per run.
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { task in
            MainActor.assumeIsolated {
                guard let task = task as? BGContinuedProcessingTask else { return task.setTaskCompleted(success: false) }
                task.expirationHandler = { Task { @MainActor in onExpire() } }
                onStart(SystemContinuedTask(task: task))
            }
        }
        guard registered else { throw ContinuedTaskError.notRegistered }
        let request = BGContinuedProcessingTaskRequest(identifier: identifier, title: title, subtitle: subtitle)
        // Queue: runs wait for each other on-device anyway (LocalTranscriptionQueue); a queued task starts
        // when room frees up. Default resources: Core ML runs on CPU and Neural Engine, no background GPU.
        request.strategy = .queue
        if #available(iOS 27, *) {
            try await BGTaskScheduler.shared.submitTaskRequest(request)  // reports every refusal reason
        } else {
            try BGTaskScheduler.shared.submit(request)
        }
    }
}

enum ContinuedTaskError: Error, LogCoded {
    case notRegistered
    var logCode: String { "notRegistered" }
    var logUnderlying: Error? { nil }
}

@available(iOS 26, *)
@MainActor
private final class SystemContinuedTask: ContinuedTask {
    private let task: BGContinuedProcessingTask

    init(task: BGContinuedProcessingTask) {
        self.task = task
        task.progress.totalUnitCount = 1000
    }

    func report(fraction: Double, subtitle: String) {
        task.progress.completedUnitCount = Int64((min(max(fraction, 0), 1) * 1000).rounded())
        if subtitle != task.subtitle { task.updateTitle(task.title, subtitle: subtitle) }
    }

    func complete(success: Bool) { task.setTaskCompleted(success: success) }
}
#endif
