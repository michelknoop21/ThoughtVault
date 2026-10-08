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

/// Seven logarithmic frequency bands, measured from actual mono PCM with Goertzel bins.
struct AudioSpectrumProcessor {
    static let frequencies: [Double] = [125, 250, 500, 1000, 2000, 4000, 6000]
    private(set) var bands = Array(repeating: Float(0), count: frequencies.count)

    mutating func process(samples: [Float], sampleRate: Double, dt: Double) -> [Float] {
        guard !samples.isEmpty, sampleRate > 0 else { return bands }
        let count = samples.count
        for (index, frequency) in Self.frequencies.enumerated() {
            var power: Double = 0
            for factor in [0.85, 1.0, 1.15] where frequency * factor < sampleRate / 2 {
                let coefficient = 2 * cos(2 * .pi * frequency * factor / sampleRate)
                var previous = 0.0, beforePrevious = 0.0
                for (i, value) in samples.enumerated() {
                    let window = 0.5 - 0.5 * cos(2 * .pi * Double(i) / Double(max(1, count - 1)))
                    let sample = value.isFinite ? Double(value) : 0
                    let next = sample * window + coefficient * previous - beforePrevious
                    beforePrevious = previous
                    previous = next
                }
                power = max(power, previous * previous + beforePrevious * beforePrevious - coefficient * previous * beforePrevious)
            }
            let amplitude = 4 * sqrt(max(0, power)) / Double(count)
            let db = 20 * log10(max(amplitude, 1e-10))
            let target = Float(pow(min(1, max(0, (db + 60) / 48)), 0.8))
            let response = target > bands[index] ? 0.025 : 0.14
            bands[index] += (target - bands[index]) * Float(1 - exp(-max(0, min(0.25, dt)) / response))
        }
        return bands
    }
}

/// Host-time positioning keeps silent device gaps in the saved audio timeline.
struct AudioCaptureTimeline {
    let sampleRate: Double
    private var origin: Double
    private var pausedAt: Double?

    init(sampleRate: Double, start: Double) {
        self.sampleRate = sampleRate
        origin = start
    }

    var isPaused: Bool { pausedAt != nil }

    mutating func setPaused(_ paused: Bool, at time: Double) {
        if paused, pausedAt == nil { pausedAt = time }
        if !paused, let start = pausedAt {
            origin += max(0, time - start)
            pausedAt = nil
        }
    }

    func framePosition(at time: Double) -> Int64 {
        Int64(max(0, (pausedAt ?? time) - origin) * sampleRate)
    }
}
