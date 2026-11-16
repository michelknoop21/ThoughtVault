import Foundation

/// How much detail a generated notule keeps. `volledig` is the complete notule as before, and every missing
/// choice falls back to it. Same texts and numbers as windows/src/services/notuleDetailLevel.ts.
enum NotuleDetailLevel: String, Codable, Sendable, CaseIterable {
    case kort, normaal, volledig

    /// UserDefaults key of the user's choice per profile id. Device-only: not in the iCloud settings sync.
    static let choicesKey = "profileDetailLevels"

    /// The user's choice for this profile, else the profile's default, else volledig.
    static func effective(for profile: Profile, defaults: UserDefaults = .standard) -> NotuleDetailLevel {
        let choices = defaults.dictionary(forKey: choicesKey) as? [String: String] ?? [:]
        return choices[profile.id].flatMap(Self.init(rawValue:)) ?? profile.detailLevel.flatMap(Self.init(rawValue:)) ?? .volledig
    }

    /// Stores the user's choice for a profile; nil removes it, so the profile's default applies again.
    static func setChoice(_ level: NotuleDetailLevel?, for profileId: String, defaults: UserDefaults = .standard) {
        var choices = defaults.dictionary(forKey: choicesKey) as? [String: String] ?? [:]
        choices[profileId] = level?.rawValue
        defaults.set(choices, forKey: choicesKey)
    }

    /// Target notule length in characters for a transcript of `transcriptCharacters` (UTF-16, like JS `.length`),
    /// rounded to a multiple of 100. Nil at volledig.
    func targetLength(transcriptCharacters: Int) -> Int? {
        let bounds: (factor: Double, low: Double, high: Double)
        switch self {
        case .kort: bounds = (0.06, 1500, 4000)
        case .normaal: bounds = (0.15, 2500, 8000)
        case .volledig: return nil
        }
        return Self.hundreds(min(max(bounds.factor * Double(transcriptCharacters), bounds.low), bounds.high))
    }

    /// The upper bound named in the prompt: 1.3 times the target, rounded to a multiple of 100.
    static func maximumLength(target: Int) -> Int { hundreds(1.3 * Double(target)) }

    private static func hundreds(_ value: Double) -> Int { Int((value / 100).rounded()) * 100 }

    /// Dutch thousands separator: 2400 becomes "2.400".
    static func dutchNumber(_ value: Int) -> String {
        value < 1000 ? String(value) : dutchNumber(value / 1000) + "." + String(format: "%03d", value % 1000)
    }

    // {L} is the target length, {M} the upper bound. The parity test in windows/ reads these texts from this file.
    static let kortBlock = "Detailniveau Kort: schrijf een beknopte notule van ongeveer {L} tekens, hooguit {M}. Neem altijd op: besluiten, acties met actiehouder en termijn, bedragen en getallen bij een besluit of actie, en ontkenningen en voorwaarden bij een besluit of actie. Laat bijzaken, achtergrond, voorbeelden, anekdotes, herhalingen en zijpaden weg; een weggelaten bijzaak is geen fout. Dit detailniveau gaat vóór het detailniveau en de secties van het profiel; laat secties weg die alleen bijzaken zouden bevatten."
    static let normaalBlock = "Detailniveau Normaal: schrijf een notule van ongeveer {L} tekens, hooguit {M}. Neem altijd op: besluiten, acties met actiehouder en termijn, bedragen en getallen bij een besluit of actie, en ontkenningen en voorwaarden bij een besluit of actie. Geef per hoofdonderwerp in één of twee zinnen de context. Laat zijpaden, anekdotes, herhalingen en details zonder gevolg voor een besluit of actie weg; een weggelaten bijzaak is geen fout. Dit detailniveau gaat vóór het detailniveau van het profiel."

    /// The block appended at the very end of the draft user message; empty at volledig, so that message is unchanged.
    func draftBlock(transcriptCharacters: Int) -> String {
        guard let target = targetLength(transcriptCharacters: transcriptCharacters) else { return "" }
        return "\n\n" + (self == .kort ? Self.kortBlock : Self.normaalBlock)
            .replacingOccurrences(of: "{L}", with: Self.dutchNumber(target))
            .replacingOccurrences(of: "{M}", with: Self.dutchNumber(Self.maximumLength(target: target)))
    }

    static let auditSuffixText = "Deze notule is bewust beknopt. Een bronzin die in de notule ontbreekt en alleen een bijzaak bevat, krijgt status minor met lege evidence in plaats van missing. minor is NOOIT toegestaan voor besluiten, acties, actiehouders, termijnen, bedragen, getallen, ontkenningen, verboden, voorwaarden, afwezigheid of open vragen; ontbreken die, dan blijft het missing. Twijfel je of iets een bijzaak is, kies missing. Gebruikersnotities (Q) zijn nooit minor."

    /// Added as a last line to the single-request audit prompt and to `coverageSystem`; empty at volledig.
    var auditSuffix: String { self == .volledig ? "" : "\n" + Self.auditSuffixText }

    /// Source statuses the content audit accepts from the model: `minor` only below volledig.
    var sourceStatuses: [String] {
        ["covered", "non_factual", "missing", "uncertain"] + (self == .volledig ? [] : ["minor"])
    }
}
