// SpeakerTranscript.swift
// ThoughtVault
//
// The shared contract for speaker-labelled transcripts. The Windows app has the same logic in
// windows/src-tauri/src/transcribe/segments.rs; shared/speakers/contract-fixture.json pins both.

import Foundation

/// One timed stretch of transcribed text: a word where the engine gives word times, else a segment.
struct TimedPiece: Codable, Equatable, Sendable {
    var start: Double
    var end: Double
    var text: String
}

extension TimedPiece {
    /// Joins the pieces of consecutive chunks onto one timeline: chunk `i` starts at `i * chunkDuration`.
    static func offset(_ chunks: [[TimedPiece]], chunkDuration: TimeInterval) -> [TimedPiece] {
        chunks.enumerated().flatMap { index, pieces in
            pieces.map { TimedPiece(start: $0.start + Double(index) * chunkDuration, end: $0.end + Double(index) * chunkDuration, text: $0.text) }
        }
    }
}

/// What a transcription engine returns. `pieces` is empty when the engine gives no timings.
struct TimedTranscript: Sendable {
    var text: String
    var pieces: [TimedPiece] = []
}

/// One turn from the speaker detector, in seconds from the start of the recording.
struct SpeakerTurn: Codable, Equatable, Sendable {
    var start: Double
    var end: Double
    var speaker: String
}

/// A run of text by one speaker. `speakerId` is "S1", "S2", ... or nil when the speaker is unknown.
struct TranscriptSegment: Codable, Equatable, Sendable {
    var start: Double
    var end: Double
    var text: String
    var speakerId: String?
}

/// A name for one speaker id. `confirmed` is false for a proposal the user has not yet accepted;
/// `evidence` says what the proposal rests on, in Dutch, for the user.
struct SpeakerName: Codable, Equatable, Sendable {
    var name: String
    var confirmed: Bool
    var evidence: String
}

enum SpeakerTranscript {
    /// A piece counts as two speakers at once when the second speaker covers this share of it.
    private static let ambiguousShare = 0.25
    /// A piece outside every turn takes the nearest turn within this many seconds.
    private static let nearestGap = 0.5

    /// Gives every piece a speaker and joins neighbours with the same speaker. A piece two people
    /// share (a segment with a change in the middle, or simultaneous speech) gets no speaker
    /// instead of a guessed one. Speakers are numbered S1, S2, ... in order of first appearance.
    static func segments(pieces: [TimedPiece], turns: [SpeakerTurn]) -> [TranscriptSegment] {
        var ids: [String: String] = [:]
        var result: [TranscriptSegment] = []
        for piece in pieces {
            let text = piece.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let speakerId = speaker(for: piece, turns: turns).map { raw -> String in
                if let known = ids[raw] { return known }
                ids[raw] = "S\(ids.count + 1)"
                return ids[raw]!
            }
            if let last = result.indices.last, result[last].speakerId == speakerId {
                result[last].end = piece.end
                result[last].text += " " + text
            } else {
                result.append(TranscriptSegment(start: piece.start, end: piece.end, text: text, speakerId: speakerId))
            }
        }
        return result
    }

    private static func speaker(for piece: TimedPiece, turns: [SpeakerTurn]) -> String? {
        var overlap: [String: Double] = [:]
        for turn in turns {
            let shared = min(piece.end, turn.end) - max(piece.start, turn.start)
            if shared > 0 { overlap[turn.speaker, default: 0] += shared }
        }
        // Sorted by name as well, so a tie never depends on dictionary order.
        let ranked = overlap.sorted { ($0.value, $1.key) > ($1.value, $0.key) }
        guard let best = ranked.first else {
            var nearest: (gap: Double, speaker: String)?
            for turn in turns {
                let gap = max(turn.start - piece.end, piece.start - turn.end, 0)
                if gap <= nearestGap, gap < (nearest?.gap ?? .infinity) { nearest = (gap, turn.speaker) }
            }
            return nearest?.speaker
        }
        if ranked.count > 1, ranked[1].value >= ambiguousShare * max(piece.end - piece.start, 1e-9) { return nil }
        return best.key
    }

    /// The transcript as the note generator reads it: one turn per line, "Spreker 2: tekst".
    /// Without any known speaker it is the plain text, as before speaker detection.
    static func text(_ segments: [TranscriptSegment]) -> String {
        guard segments.contains(where: { $0.speakerId != nil }) else {
            return segments.map(\.text).joined(separator: " ")
        }
        return segments.map { "\(label($0.speakerId)): \($0.text)" }.joined(separator: "\n")
    }

    /// "S2" becomes "Spreker 2". An unknown speaker is "Onbekende spreker", not "Onbekend": the note
    /// audit treats the bare word "onbekend" as a constraint keyword and would flag every such line.
    static func label(_ speakerId: String?) -> String {
        guard let speakerId, speakerId.hasPrefix("S") else { return "Onbekende spreker" }
        return "Spreker " + speakerId.dropFirst()
    }

    /// True when the transcript has speaker lines, so the prompt may rely on them.
    static func hasLabels(_ transcript: String) -> Bool {
        transcript.range(of: #"(?m)^Spreker [0-9]+: "#, options: .regularExpression) != nil
    }
}
