import Foundation
import os

/// One step of notule generation: names model requests in the log and the running task in the UI.
/// In the log `index` is the request's 1-based position; in a progress report it is the number of finished requests.
struct ModelStep: Sendable, Equatable {
    enum Kind: String, Sendable {
        case draft
        case chunkSummary = "chunk-summary"
        case sourceCheck = "source-check"
        case noteCheck = "note-check"
        case coverage
        case sentenceCheck = "sentence-check"
        case contextSuggestions = "context-suggestions"
    }

    let kind: Kind
    var index: Int?
    var total: Int?

    init(_ kind: Kind, _ index: Int? = nil, of total: Int? = nil) {
        self.kind = kind
        self.index = index
        self.total = total
    }

    /// The step the model requests of the current task belong to; child tasks inherit it.
    @TaskLocal static var current: ModelStep?

    var logLabel: String { index.map { "\(kind.rawValue) \($0)/\(total ?? 0)" } ?? kind.rawValue }

    /// Dutch task label, e.g. "Controle 12 van 61".
    var displayLabel: String {
        let counted = { (key: String.LocalizationValue) in String(format: String(localized: key), index ?? 0, total ?? 0) }
        switch kind {
        case .draft: return String(localized: "notule.step.draft")
        case .chunkSummary: return counted("notule.step.chunkSummary")
        case .sourceCheck: return String(localized: "notule.step.sourceCheck")
        case .noteCheck: return String(localized: "notule.step.noteCheck")
        case .coverage: return counted("notule.step.coverage")
        case .sentenceCheck: return counted("notule.step.sentenceCheck")
        case .contextSuggestions: return String(localized: "notule.step.contextSuggestions")
        }
    }
}

/// Start and end line per model request. Only metadata: the log tail is attached to support reports (DEC-064),
/// so prompt, transcript and notule text never reach it.
enum ModelRequestLog {
    private static let log = AppLog(category: "ModelRequest")
    /// Test seam: receives the lines instead of the log file.
    @TaskLocal static var sink: (@Sendable (String) -> Void)?

    static func run<T>(provider: String, model: String, system: String, user: String,
                       _ body: () async throws -> T) async throws -> T {
        let head = "step=\(ModelStep.current?.logLabel ?? "other") provider=\(provider) model=\(model) input_chars=\(system.utf16.count + user.utf16.count)"
        write("model request start \(head)", failed: false)
        let started = Date()
        let usage = OSAllocatedUnfairLock(initialState: TokenUsage())
        // A failed or cancelled request still counts; without reported tokens its usage is unknown.
        defer { UsageMeter.current?.add(step: ModelStep.current?.kind, model: model, usage: usage.withLock { $0 }) }
        do {
            let result = try await $currentUsage.withValue(usage) { try await body() }
            write("model request end \(head) ms=\(milliseconds(since: started))\(fields(usage.withLock { $0 })) outcome=ok", failed: false)
            return result
        } catch {
            write("model request end \(head) ms=\(milliseconds(since: started))\(fields(usage.withLock { $0 })) outcome=\(outcome(error))", failed: true)
            throw error
        }
    }

    /// Usage of the running request; set by `run`, filled by the provider through `report`.
    @TaskLocal private static var currentUsage: OSAllocatedUnfairLock<TokenUsage>?

    /// The provider read token counts or cost from its answer.
    static func report(_ reported: TokenUsage) {
        currentUsage?.withLock { $0.merge(reported) }
    }

    /// Numbers only, like the rest of the line; nothing when the provider reported nothing.
    private static func fields(_ usage: TokenUsage) -> String {
        [("in_tok", usage.input.map(String.init)), ("out_tok", usage.output.map(String.init)),
         ("reason_tok", usage.reasoning.map(String.init)), ("cost", usage.costUSD.map { String(format: "%.6f", $0) })]
            .compactMap { name, value in value.map { " \(name)=\($0)" } }.joined()
    }

    /// The request got HTTP 429 and is sent again after `wait` seconds.
    static func retry(wait: TimeInterval) {
        write("model request retry step=\(ModelStep.current?.logLabel ?? "other") after HTTP 429 wait_ms=\(Int(wait * 1000))", failed: false)
    }

    /// The request lost its connection and is sent once more now that the app is active again.
    static func retryAfterDrop(_ error: URLError) {
        write("model request retry step=\(ModelStep.current?.logLabel ?? "other") after \(LogRedact.describe(error)) app=active", failed: false)
    }

    static func outcome(_ error: any Error) -> String {
        if case LLMError.serverError(let code) = error { return "HTTP \(code)" }
        if case LLMError.timedOut = error { return "timed out" }
        if (error as? URLError)?.code == .timedOut { return "timed out" }
        if case LLMError.truncated = error { return "truncated" }
        if case LLMError.emptyResponse = error { return "empty" }
        if error is CancellationError || (error as? URLError)?.code == .cancelled { return "cancelled" }
        return "error " + LogRedact.describe(error)
    }

    private static func milliseconds(since start: Date) -> Int { Int(Date().timeIntervalSince(start) * 1000) }

    private static func write(_ line: String, failed: Bool) {
        if let sink { return sink(line) }
        if failed { log.warning(line) } else { log.info(line) }
    }
}
