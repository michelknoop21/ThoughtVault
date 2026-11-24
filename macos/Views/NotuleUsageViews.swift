// NotuleUsageViews.swift
// ThoughtVault
//
// Usage of a generated notule: the quiet footer line under the notule and the
// "Gebruik deze maand" rows on the Verwerking page (macOS and iOS).

import SwiftUI

/// Dutch text for notule usage. Composed in code (like `NotulenProvider.displayName`) so numbers,
/// plurals and separators stay in one place.
enum UsageText {
    /// Fixed approximation of the USD to EUR rate; amounts are shown as "ongeveer".
    static let eurPerUSD = 0.86

    private static let separator = " \u{00B7} "

    /// "2.430 tekens · 380 woorden · 33 verzoeken · ongeveer € 0,07 · 1 min 12 s · OpenRouter, mistral-large-4-0".
    /// Length comes from the shown HTML, so it stays right after an edit; older notules show only that.
    static func footer(html: String, usage: NotuleUsage?) -> String {
        let text = NotuleUsage.plainText(html)
        var parts = [counted(text.count, "teken", "tekens"), counted(NotuleUsage.words(text), "woord", "woorden")]
        if let usage {
            let provider = NotulenProvider(rawValue: usage.provider)
            parts.append(counted(usage.requests, "verzoek", "verzoeken"))
            parts.append(cost(usage, provider: provider))
            parts.append(duration(milliseconds: usage.durationMs))
            parts.append(source(usage, provider: provider))
            if usage.contentCheckSkipped { parts.append("niet automatisch gecontroleerd") }
        }
        return parts.joined(separator: separator)
    }

    static func cost(_ usage: NotuleUsage, provider: NotulenProvider?) -> String {
        switch provider?.costKind {
        case .onDevice: return "gratis, op dit apparaat"
        case .subscription: return "via je Ollama-abonnement"
        case .metered, nil: return usage.costUSD.map(euros) ?? "kosten niet bekend in de app"
        }
    }

    /// "OpenRouter, mistral-large-4-0": provider name and the model without its vendor prefix.
    static func source(_ usage: NotuleUsage, provider: NotulenProvider?) -> String {
        let name = provider?.displayName ?? usage.provider
        let model = usage.model.split(separator: "/").last.map(String.init) ?? ""
        return model.isEmpty || provider == .appleIntelligence ? name : "\(name), \(model)"
    }

    /// "ongeveer € 0,07"; below one cent "minder dan € 0,01".
    static func euros(_ usd: Double) -> String {
        let eur = usd * eurPerUSD
        if eur <= 0 { return "geen kosten" }
        if eur < 0.01 { return "minder dan € 0,01" }
        return "ongeveer € " + number(eur, fractionDigits: 2)
    }

    /// "1 min 12 s", "45 s".
    static func duration(milliseconds: Int) -> String {
        let seconds = max(0, milliseconds) / 1000
        return seconds >= 60 ? "\(seconds / 60) min \(seconds % 60) s" : "\(seconds) s"
    }

    /// "41 notules · 1.320 verzoeken · ongeveer € 3,20".
    static func month(_ month: UsageLedger.Month) -> String {
        var parts = [counted(month.notules, "notule", "notules"), counted(month.requests, "verzoek", "verzoeken")]
        if month.costUSD > 0 || month.runsWithUnknownCost == 0 { parts.append(euros(month.costUSD)) }
        return parts.joined(separator: separator)
    }

    /// Nil when every metered run had a known cost.
    static func unknownCost(_ month: UsageLedger.Month) -> String? {
        guard month.runsWithUnknownCost > 0 else { return nil }
        return "Van \(counted(month.runsWithUnknownCost, "verwerking", "verwerkingen")) zijn de kosten niet bekend in de app."
    }

    static func counted(_ count: Int, _ one: String, _ many: String) -> String {
        "\(number(Double(count))) \(count == 1 ? one : many)"
    }

    private static func number(_ value: Double, fractionDigits: Int = 0) -> String {
        value.formatted(.number.locale(Locale(identifier: "nl_NL")).precision(.fractionLength(fractionDigits)))
    }
}

/// One quiet line under a notule. Reads the stored usage of the local record, if any.
struct NotuleUsageFooter: View {
    let taskId: String
    let html: String

    var body: some View {
        Text(UsageText.footer(html: html, usage: LocalTranscriptStore.shared.record(forTaskId: taskId)?.notuleUsage))
            .font(TS.Font.caption)
            .monospacedDigit()
            .foregroundStyle(Color.labelTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }
}

/// Rows of the "Gebruik deze maand" card: this month, the previous month when it has runs, and where the cost comes from.
struct UsageMonthRows: View {
    @AppStorage(UsageLedger.key) private var ledger = Data()

    var body: some View {
        let months = UsageLedger.decode(ledger)
        let now = Date()
        let current = months[UsageLedger.monthKey(now)] ?? UsageLedger.Month()
        VStack(alignment: .leading, spacing: 8) {
            Text(UsageText.month(current))
                .font(.system(size: 15, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(HomeColor.text)
            if let unknown = UsageText.unknownCost(current) { detail(unknown) }
            detail(String(localized: "Geteld op dit apparaat."))
            if let previous = months[UsageLedger.previousMonthKey(now)] {
                Text("Vorige maand").font(.system(size: 13, weight: .medium)).foregroundStyle(HomeColor.text2)
                    .padding(.top, 6)
                Text(UsageText.month(previous))
                    .font(.system(size: 14))
                    .monospacedDigit()
                    .foregroundStyle(HomeColor.text)
                if let unknown = UsageText.unknownCost(previous) { detail(unknown) }
            }
            detail(String(localized: "De kosten zitten vooral in de controle: die toetst elke zin van de notule apart aan het gesprek."))
                .padding(.top, 6)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detail(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .monospacedDigit()
            .foregroundStyle(HomeColor.text2)
            .fixedSize(horizontal: false, vertical: true)
    }
}
