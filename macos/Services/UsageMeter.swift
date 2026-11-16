import Foundation
import os

/// Tokens and cost one model request reported. Nil means the provider did not say.
struct TokenUsage: Sendable, Equatable {
    var input: Int?
    var output: Int?
    var reasoning: Int?
    var costUSD: Double?

    /// True once the provider reported token counts.
    var isKnown: Bool { input != nil || output != nil }

    /// Later reports win per field: Anthropic sends input first and the cumulative output last.
    mutating func merge(_ other: TokenUsage) {
        input = other.input ?? input
        output = other.output ?? output
        reasoning = other.reasoning ?? reasoning
        costUSD = other.costUSD ?? costUSD
    }

    /// `usage` of an OpenAI-style answer or final stream chunk (OpenAI, OpenRouter, Ollama, LM Studio).
    /// OpenRouter adds `cost` in USD; the others have no cost field.
    static func openAI(_ value: Any?) -> TokenUsage? {
        guard let usage = value as? [String: Any] else { return nil }
        let details = usage["completion_tokens_details"] as? [String: Any]
        let result = TokenUsage(input: usage["prompt_tokens"] as? Int, output: usage["completion_tokens"] as? Int,
                                reasoning: details?["reasoning_tokens"] as? Int, costUSD: usage["cost"] as? Double)
        return result.isKnown || result.costUSD != nil ? result : nil
    }

    /// `usage` of an Anthropic message, `message_start.message` or `message_delta` event.
    static func anthropic(_ value: Any?) -> TokenUsage? {
        guard let usage = value as? [String: Any] else { return nil }
        let result = TokenUsage(input: usage["input_tokens"] as? Int, output: usage["output_tokens"] as? Int)
        return result.isKnown ? result : nil
    }
}

/// Totals of every model request of one notule run, including requests in child tasks
/// (`async let`, task groups): they inherit `UsageMeter.current`.
final class UsageMeter: Sendable {
    struct StepTotals: Codable, Sendable, Equatable {
        var requests = 0
        var inputTokens = 0
        var outputTokens = 0
    }

    struct Totals: Sendable, Equatable {
        var requests = 0
        var requestsWithUnknownUsage = 0
        var inputTokens = 0
        var outputTokens = 0
        var reasoningTokens = 0
        var knownCostUSD = 0.0
        var requestsWithoutCost = 0
        var steps: [String: StepTotals] = [:]
        /// Model of the first request, normally the draft.
        var model: String?

        /// Nil as soon as one request had no cost.
        var costUSD: Double? { requestsWithoutCost == 0 ? knownCostUSD : nil }
    }

    /// The meter the model requests of the current task report into; child tasks inherit it.
    @TaskLocal static var current: UsageMeter?

    private let state = OSAllocatedUnfairLock(initialState: Totals())
    private let started = ContinuousClock.now

    var totals: Totals { state.withLock { $0 } }

    /// Wall-clock time since the meter was created.
    var elapsedMilliseconds: Int {
        let elapsed = ContinuousClock.now - started
        return Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
    }

    /// One finished, failed or cancelled request; usage without token counts counts as unknown.
    func add(step: ModelStep.Kind?, model: String, usage: TokenUsage) {
        state.withLock { totals in
            totals.requests += 1
            totals.model = totals.model ?? model
            if !usage.isKnown { totals.requestsWithUnknownUsage += 1 }
            totals.inputTokens += usage.input ?? 0
            totals.outputTokens += usage.output ?? 0
            totals.reasoningTokens += usage.reasoning ?? 0
            if let cost = usage.costUSD { totals.knownCostUSD += cost } else { totals.requestsWithoutCost += 1 }
            let key = step?.rawValue ?? "other"
            totals.steps[key, default: StepTotals()].requests += 1
            totals.steps[key, default: StepTotals()].inputTokens += usage.input ?? 0
            totals.steps[key, default: StepTotals()].outputTokens += usage.output ?? 0
        }
    }
}

/// Length, requests, tokens, cost and duration of one generated notule; stored as JSON on the record.
struct NotuleUsage: Codable, Sendable, Equatable {
    var provider: String
    var model: String
    var transcriptCharacters: Int
    var notuleCharacters: Int
    var notuleWords: Int
    /// Counted like the audit's notule units, so it compares with `NotuleAudit.maxNoteChecks`.
    var notuleSentences: Int
    var requests: Int
    var requestsWithUnknownUsage: Int
    var inputTokens: Int
    var outputTokens: Int
    var reasoningTokens: Int
    var costUSD: Double?
    var durationMs: Int
    var steps: [String: UsageMeter.StepTotals]
    var contentCheckSkipped: Bool
    /// The audit's own message when the content check could not run; the audit has no reason codes.
    var contentCheckSkipReason: String?

    init(provider: String, model: String, transcriptCharacters: Int, notuleHtml: String, notuleSentences: Int,
         totals: UsageMeter.Totals, durationMs: Int, contentCheckSkipReason: String?) {
        let text = NotuleUsage.plainText(notuleHtml)
        self.provider = provider
        self.model = model
        self.transcriptCharacters = transcriptCharacters
        self.notuleCharacters = text.count
        self.notuleWords = NotuleUsage.words(text)
        self.notuleSentences = notuleSentences
        self.requests = totals.requests
        self.requestsWithUnknownUsage = totals.requestsWithUnknownUsage
        self.inputTokens = totals.inputTokens
        self.outputTokens = totals.outputTokens
        self.reasoningTokens = totals.reasoningTokens
        self.costUSD = totals.costUSD
        self.durationMs = durationMs
        self.steps = totals.steps
        self.contentCheckSkipped = contentCheckSkipReason != nil
        self.contentCheckSkipReason = contentCheckSkipReason
    }

    static func plainText(_ html: String) -> String { HTMLPlainText.from(html) }
    static func words(_ text: String) -> Int { text.split(whereSeparator: { $0.isWhitespace }).count }

    var json: String? { (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) } }

    init?(json: String?) {
        guard let data = json?.data(using: .utf8), let usage = try? JSONDecoder().decode(Self.self, from: data) else { return nil }
        self = usage
    }
}

extension NotulenProvider {
    /// How a run with this provider is paid for.
    enum CostKind { case onDevice, subscription, metered }

    var costKind: CostKind {
        switch self {
        case .ollama, .lmStudio, .appleIntelligence, .cloud: return .onDevice
        case .ollamaCloud: return .subscription
        case .openAI, .anthropic, .openAICompatible, .openRouter: return .metered
        }
    }
}

/// Monthly totals of model use on this device, in UserDefaults. Not synced: each device counts its own runs.
enum UsageLedger {
    struct Month: Codable, Sendable, Equatable {
        var notules = 0
        var requests = 0
        var costUSD = 0.0
        var runsWithUnknownCost = 0
    }

    static let key = "usageLedger"
    private static let lock = OSAllocatedUnfairLock()

    /// Adds one run. `notule` is false for a failed run and for the context-suggestions request.
    static func record(_ totals: UsageMeter.Totals, provider: NotulenProvider, notule: Bool,
                       date: Date = Date(), defaults: UserDefaults = .standard) {
        guard totals.requests > 0 || notule else { return }
        lock.withLockUnchecked {
            var months = load(defaults)
            var month = months[monthKey(date)] ?? Month()
            if notule { month.notules += 1 }
            month.requests += totals.requests
            if provider.costKind == .metered {
                if let cost = totals.costUSD { month.costUSD += cost } else { month.runsWithUnknownCost += 1 }
            }
            months[monthKey(date)] = month
            if let data = try? JSONEncoder().encode(months) { defaults.set(data, forKey: key) }
        }
    }

    static func load(_ defaults: UserDefaults = .standard) -> [String: Month] {
        decode(defaults.data(forKey: key))
    }

    static func decode(_ data: Data?) -> [String: Month] {
        data.flatMap { try? JSONDecoder().decode([String: Month].self, from: $0) } ?? [:]
    }

    /// "yyyy-MM" in the device's calendar and time zone.
    static func monthKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
    }

    static func previousMonthKey(_ date: Date, calendar: Calendar = .current) -> String {
        monthKey(calendar.date(byAdding: .month, value: -1, to: date) ?? date, calendar: calendar)
    }
}
