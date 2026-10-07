import Foundation

// Cross-platform amplitude envelope for the live mic visualisation.
// Pipeline: dBFS → noise-floor tracking → soft gate → range map → response
// curve → dt-based attack/release → scalar 0..1.
//
// IMPORTANT: constants must stay identical to EnvelopeConfig in
// windows/src-tauri/src/audio/envelope.rs. Both are verified against the same
// fixture: tests/fixtures/envelope-fixture.json.

struct AudioEnvelopeConfig {
    static let analysisWindowMs: Double = 30
    static let publishRateHz: Double = 30
    static let initialNoiseFloorDb: Float = -60
    static let minimumNoiseFloorDb: Float = -75
    static let maximumNoiseFloorDb: Float = -35
    static let gateStartOffsetDb: Float = 3
    static let gateEndOffsetDb: Float = 9
    static let visualMinimumFloorDb: Float = -55
    static let visualMinimumOffsetDb: Float = 6
    static let visualMaximumDb: Float = -8
    static let responseExponent: Float = 0.65
    static let attackMs: Double = 35
    static let releaseMs: Double = 220
    static let silenceThreshold: Float = 0.015
    /// 90 samples @ 30 Hz = 3.0 s of scrolling history in the waveform.
    static let historyLength = 90
    /// Window (ms) of dB samples used for the noise-floor percentile.
    static let floorHistoryMs: Double = 2000
    /// dB above the floor that counts as clear speech (freezes upward floor drift).
    static let speechOffsetDb: Float = 12
    static let floorFallTcMs: Double = 500
    static let floorRiseTcMs: Double = 2000
}

struct AudioEnvelopeProcessor {

    private var floorDb: Float = AudioEnvelopeConfig.initialNoiseFloorDb
    private var smoothed: Float = 0
    /// Recent (db, dtMs) samples covering ~floorHistoryMs.
    private var history: [(db: Float, dtMs: Double)] = []
    private var historyMs: Double = 0

    // Last pipeline values, for the DEBUG overlay.
    private(set) var lastDb: Float = -120
    private(set) var lastGate: Float = 0
    private(set) var lastTarget: Float = 0

    /// Feed one dBFS measurement; `dt` is elapsed time in seconds since the
    /// previous call. Returns the envelope scalar 0..1.
    mutating func process(db rawDb: Float, dt: Double) -> Float {
        let db = min(0, max(-120, rawDb.isFinite ? rawDb : -120))
        let dtMs = max(1, min(250, dt * 1000))

        // Noise floor: ~2 s history, 20th percentile as candidate.
        history.append((db, dtMs))
        historyMs += dtMs
        while historyMs - history[0].dtMs > AudioEnvelopeConfig.floorHistoryMs, history.count > 1 {
            historyMs -= history.removeFirst().dtMs
        }
        let sorted = history.map(\.db).sorted()
        let candidate = sorted[sorted.count / 5]
        let isSpeech = db > floorDb + AudioEnvelopeConfig.speechOffsetDb
        if candidate < floorDb {
            floorDb += (candidate - floorDb) * alpha(dtMs: dtMs, tcMs: AudioEnvelopeConfig.floorFallTcMs)
        } else if !isSpeech {
            floorDb += (candidate - floorDb) * alpha(dtMs: dtMs, tcMs: AudioEnvelopeConfig.floorRiseTcMs)
        }
        floorDb = min(AudioEnvelopeConfig.maximumNoiseFloorDb,
                      max(AudioEnvelopeConfig.minimumNoiseFloorDb, floorDb))

        // Soft gate above the floor.
        let gate = smoothstep(floorDb + AudioEnvelopeConfig.gateStartOffsetDb,
                              floorDb + AudioEnvelopeConfig.gateEndOffsetDb,
                              db)

        // Fixed dynamic-range map + response curve.
        let visMin = max(floorDb + AudioEnvelopeConfig.visualMinimumOffsetDb,
                         AudioEnvelopeConfig.visualMinimumFloorDb)
        let visMax = AudioEnvelopeConfig.visualMaximumDb
        let normalized = min(1, max(0, (db - visMin) / (visMax - visMin)))
        let target = pow(normalized, AudioEnvelopeConfig.responseExponent) * gate

        // Time-normalized attack/release (frame-rate independent).
        let tcMs = target > smoothed ? AudioEnvelopeConfig.attackMs : AudioEnvelopeConfig.releaseMs
        smoothed += (target - smoothed) * alpha(dtMs: dtMs, tcMs: tcMs)

        lastDb = db
        lastGate = gate
        lastTarget = target
        return smoothed < AudioEnvelopeConfig.silenceThreshold ? 0 : smoothed
    }

    mutating func reset() {
        floorDb = AudioEnvelopeConfig.initialNoiseFloorDb
        smoothed = 0
        history.removeAll()
        historyMs = 0
        lastDb = -120
        lastGate = 0
        lastTarget = 0
    }

    var noiseFloorDb: Float { floorDb }

    private func alpha(dtMs: Double, tcMs: Double) -> Float {
        Float(1 - exp(-dtMs / tcMs))
    }

    private func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
        let t = min(1, max(0, (x - edge0) / (edge1 - edge0)))
        return t * t * (3 - 2 * t)
    }
}
