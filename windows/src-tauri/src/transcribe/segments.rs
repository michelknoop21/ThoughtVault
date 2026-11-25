//! The shared contract for speaker-labelled transcripts. The macOS app has the same logic in
//! macos/Services/SpeakerTranscript.swift; shared/speakers/contract-fixture.json pins both.

use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

/// One timed stretch of transcribed text: a word where the engine gives word times, else a segment.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct TimedPiece { pub start: f64, pub end: f64, pub text: String }

/// What a transcription engine returns. `pieces` is empty when the engine gives no timings.
/// Deserializes straight from the faster-whisper worker and from a `verbose_json` cloud reply,
/// which both name the pieces `segments`; their extra fields are ignored.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct TimedTranscript {
    pub text: String,
    #[serde(default, alias = "segments")]
    pub pieces: Vec<TimedPiece>,
}

/// Joins the pieces of consecutive chunks onto one timeline: chunk `i` starts at `i * chunk_seconds`.
pub fn offset(chunks: Vec<Vec<TimedPiece>>, chunk_seconds: f64) -> Vec<TimedPiece> {
    chunks.into_iter().enumerate().flat_map(|(index, pieces)| {
        let shift = index as f64 * chunk_seconds;
        pieces.into_iter().map(move |p| TimedPiece { start: p.start + shift, end: p.end + shift, text: p.text })
    }).collect()
}

/// One turn from the speaker detector, in seconds from the start of the recording.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SpeakerTurn { pub start: f64, pub end: f64, pub speaker: String }

/// A run of text by one speaker. `speaker_id` is "S1", "S2", ... or None when the speaker is unknown.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct TranscriptSegment {
    pub start: f64,
    pub end: f64,
    pub text: String,
    #[serde(rename = "speakerId")]
    pub speaker_id: Option<String>,
}

/// A piece counts as two speakers at once when the second speaker covers this share of it.
const AMBIGUOUS_SHARE: f64 = 0.25;
/// A piece outside every turn takes the nearest turn within this many seconds.
const NEAREST_GAP: f64 = 0.5;

/// Gives every piece a speaker and joins neighbours with the same speaker. A piece two people
/// share (a segment with a change in the middle, or simultaneous speech) gets no speaker
/// instead of a guessed one. Speakers are numbered S1, S2, ... in order of first appearance.
pub fn segments(pieces: &[TimedPiece], turns: &[SpeakerTurn]) -> Vec<TranscriptSegment> {
    let mut ids: BTreeMap<String, String> = BTreeMap::new();
    let mut result: Vec<TranscriptSegment> = Vec::new();
    for piece in pieces {
        let text = piece.text.trim();
        if text.is_empty() { continue; }
        let speaker_id = speaker_for(piece, turns).map(|raw| {
            let next = format!("S{}", ids.len() + 1);
            ids.entry(raw).or_insert(next).clone()
        });
        match result.last_mut() {
            Some(last) if last.speaker_id == speaker_id => {
                last.end = piece.end;
                last.text.push(' ');
                last.text.push_str(text);
            }
            _ => result.push(TranscriptSegment { start: piece.start, end: piece.end, text: text.to_string(), speaker_id }),
        }
    }
    result
}

fn speaker_for(piece: &TimedPiece, turns: &[SpeakerTurn]) -> Option<String> {
    let mut overlap: BTreeMap<&str, f64> = BTreeMap::new();
    for turn in turns {
        let shared = piece.end.min(turn.end) - piece.start.max(turn.start);
        if shared > 0.0 { *overlap.entry(turn.speaker.as_str()).or_insert(0.0) += shared; }
    }
    // Sorted by name as well, so a tie never depends on map order.
    let mut ranked: Vec<(&str, f64)> = overlap.into_iter().collect();
    ranked.sort_by(|a, b| b.1.total_cmp(&a.1).then(b.0.cmp(a.0)));
    let Some(best) = ranked.first() else {
        let mut nearest: Option<(f64, &str)> = None;
        for turn in turns {
            let gap = (turn.start - piece.end).max(piece.start - turn.end).max(0.0);
            if gap <= NEAREST_GAP && gap < nearest.map_or(f64::INFINITY, |n| n.0) { nearest = Some((gap, &turn.speaker)); }
        }
        return nearest.map(|n| n.1.to_string());
    };
    if ranked.len() > 1 && ranked[1].1 >= AMBIGUOUS_SHARE * (piece.end - piece.start).max(1e-9) { return None; }
    Some(best.0.to_string())
}

/// The transcript as the note generator reads it: one turn per line, "Spreker 2: tekst".
/// Without any known speaker it is the plain text, as before speaker detection.
pub fn text(segments: &[TranscriptSegment]) -> String {
    if segments.iter().all(|s| s.speaker_id.is_none()) {
        return segments.iter().map(|s| s.text.as_str()).collect::<Vec<_>>().join(" ");
    }
    segments.iter().map(|s| format!("{}: {}", label(s.speaker_id.as_deref()), s.text)).collect::<Vec<_>>().join("\n")
}

/// "S2" becomes "Spreker 2". An unknown speaker is "Onbekende spreker", not "Onbekend": the note
/// audit treats the bare word "onbekend" as a constraint keyword and would flag every such line.
pub fn label(speaker_id: Option<&str>) -> String {
    match speaker_id.and_then(|id| id.strip_prefix('S')) {
        Some(number) => format!("Spreker {number}"),
        None => "Onbekende spreker".to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[derive(Deserialize)]
    struct Case { name: String, pieces: Vec<TimedPiece>, turns: Vec<SpeakerTurn>, segments: Vec<TranscriptSegment>, text: String }
    #[derive(Deserialize)]
    struct Fixture { cases: Vec<Case> }

    #[test]
    fn chunk_pieces_are_shifted_onto_one_timeline() {
        let piece = |start: f64, end: f64, text: &str| TimedPiece { start, end, text: text.into() };
        assert_eq!(offset(vec![vec![piece(1.0, 2.0, "een")], vec![], vec![piece(0.5, 1.0, "twee")]], 60.0),
                   vec![piece(1.0, 2.0, "een"), piece(120.5, 121.0, "twee")]);
    }

    #[test]
    fn worker_and_verbose_replies_deserialize_and_plain_replies_have_no_pieces() {
        let verbose: TimedTranscript = serde_json::from_str(r#"{"text":"Ja. Doe ik.","language":"dutch","segments":[{"id":0,"start":0.0,"end":1.2,"text":" Ja.","tokens":[1]}]}"#).unwrap();
        assert_eq!(verbose.pieces, vec![TimedPiece { start: 0.0, end: 1.2, text: " Ja.".into() }]);
        let plain: TimedTranscript = serde_json::from_str(r#"{"text":"Hallo"}"#).unwrap();
        assert_eq!(plain, TimedTranscript { text: "Hallo".into(), pieces: vec![] });
    }

    /// The same file the Swift tests read, so both implementations stay equal.
    #[test]
    fn shared_contract_fixture() {
        let fixture: Fixture = serde_json::from_str(include_str!("../../../../shared/speakers/contract-fixture.json")).unwrap();
        assert_eq!(fixture.cases.len(), 5);
        for case in fixture.cases {
            let got = segments(&case.pieces, &case.turns);
            assert_eq!(got.len(), case.segments.len(), "{}", case.name);
            for (g, w) in got.iter().zip(&case.segments) {
                assert_eq!((&g.text, &g.speaker_id), (&w.text, &w.speaker_id), "{}", case.name);
                assert!((g.start - w.start).abs() < 1e-9 && (g.end - w.end).abs() < 1e-9, "{}", case.name);
            }
            assert_eq!(text(&got), case.text, "{}", case.name);
        }
    }
}
