// GlossaryAutoMatch.swift
// ThoughtVault
//
// Finds misheard spellings of glossary terms and directory names in a transcript, lets the
// minutes model confirm each one in context, and replaces the confirmed occurrences (DEC-062).
// Port source of windows/src/services/glossaryAutoMatch.ts; tests/fixtures/glossary-automatch.json
// keeps both equal. Ranges are UTF-16 (NSString), like JavaScript string indices.

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.buildmind.ThoughtVault", category: "GlossaryAutoMatch")

struct MatchTarget: Equatable, Sendable {
    enum Kind: Sendable { case term, person }
    var kind: Kind
    var id: String
    var canonical: String
    var note: String?
    /// Spellings replaced anyway (glossary variants): never a candidate.
    var fixed: [String]
    /// Known spellings (learned, person aliases): always a candidate, still checked in context.
    var known: [String]
}

struct MatchCandidate: Sendable {
    var heard: String
    var range: NSRange
    var sentence: String
    var target: MatchTarget
    var similarity: Double
}

struct GlossaryMatchResult: Sendable {
    var text: String
    var learned: [(target: MatchTarget, heard: String)]
}

enum GlossaryAutoMatch {
    static let maxCandidates = 12
    private static let maxPerSpelling = 3
    private static let promptBudget = 1500
    private static let sentenceLimit = 160

    // MARK: - Normalization

    /// Lowercase without accents.
    static func fold(_ text: String) -> String {
        text.folding(options: .diacriticInsensitive, locale: nil).lowercased()
    }
    private static func compact(_ text: String) -> String {
        String(String.UnicodeScalarView(fold(text).unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }))
    }
    /// Folded words separated by one space: "Kuber netes" differs from "Kubernetes" here, not in `compact`.
    private static func words(_ text: String) -> String {
        fold(text).replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
    /// Dutch sound-alikes made equal: ph/f, ch/g, ij/ei, ou/au, y/j, c/k, v/f, z/s, double letters.
    static func phonetic(_ text: String) -> String {
        var p = compact(text)
        for (from, to) in [("ph", "f"), ("ch", "g"), ("ij", "3"), ("ei", "3"), ("ou", "4"), ("au", "4"), ("y", "j"), ("c", "k"), ("v", "f"), ("z", "s")] {
            p = p.replacingOccurrences(of: from, with: to)
        }
        return p.replacingOccurrences(of: #"(.)\1+"#, with: "$1", options: .regularExpression)
    }
    /// Sound key: first sound plus the consonant skeleton of `phonetic`.
    static func soundKey(_ text: String) -> String {
        let p = phonetic(text)
        guard let first = p.first else { return "" }
        return String(first) + p.dropFirst().filter { !"aeiou34".contains($0) }
    }
    static func levenshtein(_ a: String, _ b: String) -> Int {
        let x = Array(a.unicodeScalars), y = Array(b.unicodeScalars)
        var row = Array(0...y.count)
        for i in 1...max(x.count, 1) where !x.isEmpty {
            var next = [i] + Array(repeating: 0, count: y.count)
            for j in stride(from: 1, through: y.count, by: 1) {
                next[j] = min(row[j] + 1, next[j - 1] + 1, row[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1))
            }
            row = next
        }
        return row[y.count]
    }
    private static func ratio(_ a: String, _ b: String) -> Double {
        let longest = max(a.unicodeScalars.count, b.unicodeScalars.count)
        return longest == 0 ? 0 : 1 - Double(levenshtein(a, b)) / Double(longest)
    }
    /// Best of the plain and the phonetic similarity, 0...1.
    static func similarity(_ a: String, _ b: String) -> Double {
        max(ratio(compact(a), compact(b)), ratio(phonetic(a), phonetic(b)))
    }

    // MARK: - Candidates

    /// Glossary terms of `profileId` and directory people, as match targets.
    static func targets(entries: [PersonalCorrection], people: [(id: String, name: String, aliases: [String])], profileId: String?) -> [MatchTarget] {
        let terms = PersonalCorrections.active(entries, profileId: profileId).map {
            MatchTarget(kind: .term, id: $0.id, canonical: $0.canonical.trimmingCharacters(in: .whitespacesAndNewlines), note: $0.note, fixed: $0.variants, known: $0.learned ?? [])
        }
        // A partial name ("Michel" for "Michel Knoop") stays context only: replacing it would change every mention.
        let persons = people.map { person -> MatchTarget in
            let nameWords = Set(fold(person.name).split(whereSeparator: \.isWhitespace))
            let known = person.aliases.filter { !fold($0).split(whereSeparator: \.isWhitespace).allSatisfy(nameWords.contains) }
            return MatchTarget(kind: .person, id: person.id, canonical: person.name.trimmingCharacters(in: .whitespacesAndNewlines), fixed: [], known: known)
        }
        return (terms + persons).filter { !$0.canonical.isEmpty }
    }

    private static func sentence(in text: NSString, around range: NSRange) -> String {
        let terminators = CharacterSet(charactersIn: ".!?\n")
        let before = text.rangeOfCharacter(from: terminators, options: .backwards, range: NSRange(location: 0, length: range.location))
        let start = before.location == NSNotFound ? 0 : before.location + 1
        let afterStart = NSMaxRange(range)
        let after = text.rangeOfCharacter(from: terminators, options: [], range: NSRange(location: afterStart, length: text.length - afterStart))
        let end = after.location == NSNotFound ? text.length : after.location + 1
        let raw = text.substring(with: NSRange(location: start, length: end - start))
        let sentence = raw.trimmingCharacters(in: .whitespacesAndNewlines) as NSString
        guard sentence.length > sentenceLimit else { return sentence as String }
        let leading = (raw as NSString).length - (raw.drop { $0.isWhitespace || $0.isNewline } as Substring).utf16.count
        let offset = range.location - start - leading
        let from = max(0, min(offset - sentenceLimit / 2, sentence.length - sentenceLimit))
        return sentence.substring(with: NSRange(location: from, length: sentenceLimit)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Candidate occurrences in transcript order, chosen best first, without LLM.
    static func candidates(in transcript: String, targets: [MatchTarget], dismissed: [String]) -> [MatchCandidate] {
        let text = transcript as NSString
        let regex = try! NSRegularExpression(pattern: #"[\p{L}\p{N}][\p{L}\p{N}'’-]*"#)
        let spans = regex.matches(in: transcript, range: NSRange(location: 0, length: text.length)).map(\.range)
        // N-grams of 1 to 3 words, normalized once for all targets.
        typealias Gram = (range: NSRange, heard: String, plain: String, spaced: String)
        let grams: [[Gram]] = (1...3).map { n in
            spans.count < n ? [] : (0...(spans.count - n)).map { i in
                let range = NSUnionRange(spans[i], spans[i + n - 1])
                let heard = text.substring(with: range)
                return (range, heard, compact(heard), words(heard))
            }
        }
        let correct = Set(targets.map { words($0.canonical) })
        let skip = Set(dismissed)
        var found: [MatchCandidate] = []
        var scores: [String: Double] = [:]
        for target in targets {
            let size = target.canonical.split(whereSeparator: \.isWhitespace).count
            let fixed = Set(target.fixed.map(words)), known = Set(target.known.map(words))
            let key = soundKey(target.canonical)
            let length = compact(target.canonical).count
            for n in max(1, size - 1)...min(3, size + 1) {
                for gram in grams[n - 1] {
                    guard gram.plain.count >= 4, !correct.contains(gram.spaced), !fixed.contains(gram.spaced),
                          !skip.contains(PersonalCorrections.learnedKey(canonical: target.canonical, heard: gram.heard)) else { continue }
                    let cacheKey = target.id + "\u{0}" + gram.spaced
                    let score: Double
                    if let cached = scores[cacheKey] { score = cached } else {
                        if known.contains(gram.spaced) { score = 1 }
                        else if Double(abs(gram.plain.count - length)) / Double(max(gram.plain.count, length)) > 0.5 { score = 0 }
                        else {
                            let s = similarity(gram.heard, target.canonical)
                            score = s >= 0.75 || (s >= 0.5 && soundKey(gram.heard) == key) ? s : 0
                        }
                        scores[cacheKey] = score
                    }
                    if score > 0 { found.append(MatchCandidate(heard: gram.heard, range: gram.range, sentence: "", target: target, similarity: score)) }
                }
            }
        }
        // Best first; a span is one thing, and one frequent spelling may not take every slot.
        // Stable order for equal scores, like Array.prototype.sort.
        let ordered = found.enumerated().sorted {
            ($0.element.similarity, -$0.element.range.location, -$0.offset) > ($1.element.similarity, -$1.element.range.location, -$1.offset)
        }.map(\.element)
        var chosen: [MatchCandidate] = []
        var perSpelling: [String: Int] = [:]
        for candidate in ordered {
            guard chosen.count < maxCandidates else { break }
            let spelling = candidate.target.id + "\u{0}" + words(candidate.heard)
            guard perSpelling[spelling, default: 0] < maxPerSpelling,
                  !chosen.contains(where: { NSIntersectionRange($0.range, candidate.range).length > 0 }) else { continue }
            perSpelling[spelling, default: 0] += 1
            var picked = candidate
            picked.sentence = sentence(in: text, around: candidate.range)
            chosen.append(picked)
        }
        return chosen.sorted { $0.range.location < $1.range.location }
    }

    // MARK: - Prompt and answer

    static let system = "Je controleert een spraaktranscriptie. Elke regel noemt een gehoord woord, de zin waarin het staat en een bekende naam of term. Beoordeel per regel of het gehoorde woord in die zin een verkeerd verstane vorm van die naam of term is. Antwoord alleen met het nummer en ja of nee, één regel per nummer, bijvoorbeeld: 1 ja"

    /// One line per candidate; trailing candidates are dropped to stay within the prompt budget.
    static func prompt(_ candidates: [MatchCandidate]) -> (user: String, count: Int) {
        var lines: [String] = [], used = system.utf16.count
        for (index, c) in candidates.enumerated() {
            let note = c.target.note.map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80)) } ?? ""
            let line = "\(index + 1). \"\(c.heard)\" in: \(c.sentence) | bedoeld: \(c.target.canonical)" + (note.isEmpty ? "" : " (\(note))")
            guard used + line.utf16.count + 1 <= promptBudget else { break }
            lines.append(line); used += line.utf16.count + 1
        }
        return (lines.joined(separator: "\n"), lines.count)
    }

    /// Numbers answered "ja"; anything unreadable or contradictory counts as no.
    static func parseAnswers(_ answer: String, count: Int) -> Set<Int> {
        let regex = try! NSRegularExpression(pattern: #"^\s*(\d+)\s*[.):-]?\s*(ja|nee)\b"#, options: .caseInsensitive)
        var yes = Set<Int>(), no = Set<Int>()
        for line in answer.components(separatedBy: .newlines) {
            let ns = line as NSString
            guard let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
                  let n = Int(ns.substring(with: match.range(at: 1))), n >= 1, n <= count else { continue }
            if ns.substring(with: match.range(at: 2)).lowercased() == "ja" { yes.insert(n) } else { no.insert(n) }
        }
        return yes.subtracting(no)
    }

    /// Replaces the confirmed occurrences; a spelling is learned only when none of its occurrences got no.
    static func apply(_ transcript: String, candidates: [MatchCandidate], yes: Set<Int>) -> GlossaryMatchResult {
        let text = NSMutableString(string: transcript)
        for (index, c) in candidates.enumerated().reversed() where yes.contains(index + 1) {
            text.replaceCharacters(in: c.range, with: c.target.canonical)
        }
        var verdicts: [(key: String, target: MatchTarget, heard: String, yes: Bool, no: Bool)] = []
        for (index, c) in candidates.enumerated() {
            let key = c.target.id + "\u{0}" + words(c.heard)
            if let i = verdicts.firstIndex(where: { $0.key == key }) {
                if yes.contains(index + 1) { verdicts[i].yes = true } else { verdicts[i].no = true }
            } else {
                verdicts.append((key, c.target, c.heard, yes.contains(index + 1), !yes.contains(index + 1)))
            }
        }
        let learned = verdicts.filter { v in v.yes && !v.no && !v.target.known.contains { words($0) == words(v.heard) } }
            .map { (target: $0.target, heard: $0.heard) }
        return GlossaryMatchResult(text: text as String, learned: learned)
    }

    /// Whole step: candidates, one model call, replacements. Any failure, a timeout or no candidates
    /// leave the transcript unchanged, so the minutes continue as before.
    static func run(_ transcript: String, targets: [MatchTarget], dismissed: [String], timeout: Duration = .seconds(20),
                    complete: @escaping @Sendable (String, String) async throws -> String) async -> GlossaryMatchResult {
        let unchanged = GlossaryMatchResult(text: transcript, learned: [])
        let all = candidates(in: transcript, targets: targets, dismissed: dismissed)
        let (user, count) = prompt(all)
        guard count > 0 else { return unchanged }
        do {
            let answer = try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask { try await complete(system, user) }
                group.addTask { try await Task.sleep(for: timeout); throw CancellationError() }
                defer { group.cancelAll() }
                return try await group.next()!
            }
            return apply(transcript, candidates: Array(all.prefix(count)), yes: parseAnswers(answer, count: count))
        } catch {
            logger.notice("Automatic glossary match skipped: \(error.localizedDescription, privacy: .public)")
            return unchanged
        }
    }

    // MARK: - App wiring

    /// Matches against the glossary and the directory, and learns confirmed spellings: a term as
    /// `learned`, a person as alias, under source "automatisch:<taskId>". Returns the transcript
    /// to generate from; the stored transcription is not changed.
    @MainActor
    static func matchGlossary(_ transcript: String, corrections: [PersonalCorrection], profileId: String,
                              service: any LLMService, taskId: String) async -> String {
        let directory = PersonDirectoryService.shared.directoryPeople()
        let result = await run(transcript, targets: targets(entries: corrections, people: directory.map { ($0.id, $0.name, $0.aliases) }, profileId: profileId),
                               dismissed: PersonalCorrections.dismissed()) { system, user in
            try await service.complete(system: system, user: user)
        }
        let source = "automatisch:\(taskId)"
        for (target, heard) in result.learned {
            do {
                switch target.kind {
                case .person:
                    guard let person = PersonDirectoryService.shared.directoryPeople().first(where: { $0.id == target.id }) else { continue }
                    try PersonDirectoryService.shared.update(person, source: source) { $0.aliases.append(heard) }
                case .term:
                    guard var entry = try PersonalCorrections.load().first(where: { $0.id == target.id }) else { continue }
                    entry.learned = (entry.learned ?? []) + [heard]
                    try PersonalCorrections.saveRecording(entry, source: source)
                }
            } catch {
                logger.error("Learning a spelling failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        return result.text
    }
}
