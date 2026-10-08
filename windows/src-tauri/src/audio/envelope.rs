// Cross-platform amplitude envelope for the live mic visualisation.
// Pipeline: dBFS → noise-floor tracking → soft gate → range map → response
// curve → dt-based attack/release → scalar 0..1.
//
// IMPORTANT: constants must stay identical to AudioEnvelopeConfig in
// macos/Services/AudioEnvelopeProcessor.swift. Both are verified against the
// same fixture: tests/fixtures/envelope-fixture.json.

pub struct EnvelopeConfig;

impl EnvelopeConfig {
    pub const PUBLISH_RATE_HZ: f64 = 30.0;
    pub const INITIAL_NOISE_FLOOR_DB: f32 = -60.0;
    pub const MINIMUM_NOISE_FLOOR_DB: f32 = -75.0;
    pub const MAXIMUM_NOISE_FLOOR_DB: f32 = -35.0;
    pub const GATE_START_OFFSET_DB: f32 = 3.0;
    pub const GATE_END_OFFSET_DB: f32 = 9.0;
    pub const VISUAL_MINIMUM_FLOOR_DB: f32 = -55.0;
    pub const VISUAL_MINIMUM_OFFSET_DB: f32 = 6.0;
    pub const VISUAL_MAXIMUM_DB: f32 = -8.0;
    pub const RESPONSE_EXPONENT: f32 = 0.65;
    pub const ATTACK_MS: f64 = 35.0;
    pub const RELEASE_MS: f64 = 220.0;
    pub const SILENCE_THRESHOLD: f32 = 0.015;
    /// Window (ms) of dB samples used for the noise-floor percentile.
    pub const FLOOR_HISTORY_MS: f64 = 2000.0;
    /// dB above the floor that counts as clear speech (freezes upward drift).
    pub const SPEECH_OFFSET_DB: f32 = 12.0;
    pub const FLOOR_FALL_TC_MS: f64 = 500.0;
    pub const FLOOR_RISE_TC_MS: f64 = 2000.0;
}

pub struct EnvelopeProcessor {
    floor_db: f32,
    smoothed: f32,
    /// Recent (db, dt_ms) samples covering ~FLOOR_HISTORY_MS.
    history: std::collections::VecDeque<(f32, f64)>,
    history_ms: f64,
}

impl EnvelopeProcessor {
    pub fn new() -> Self {
        Self {
            floor_db: EnvelopeConfig::INITIAL_NOISE_FLOOR_DB,
            smoothed: 0.0,
            history: std::collections::VecDeque::new(),
            history_ms: 0.0,
        }
    }

    /// Feed one dBFS measurement; `dt` is elapsed seconds since the previous
    /// call. Returns the envelope scalar 0..1.
    pub fn process(&mut self, raw_db: f32, dt: f64) -> f32 {
        let db = if raw_db.is_finite() { raw_db } else { -120.0 }.clamp(-120.0, 0.0);
        let dt_ms = (dt * 1000.0).clamp(1.0, 250.0);

        // Noise floor: ~2 s history, 20th percentile as candidate.
        self.history.push_back((db, dt_ms));
        self.history_ms += dt_ms;
        while self.history.len() > 1
            && self.history_ms - self.history.front().unwrap().1 > EnvelopeConfig::FLOOR_HISTORY_MS
        {
            self.history_ms -= self.history.pop_front().unwrap().1;
        }
        let mut sorted: Vec<f32> = self.history.iter().map(|&(d, _)| d).collect();
        sorted.sort_by(|a, b| a.partial_cmp(b).unwrap());
        let candidate = sorted[sorted.len() / 5];
        let is_speech = db > self.floor_db + EnvelopeConfig::SPEECH_OFFSET_DB;
        if candidate < self.floor_db {
            self.floor_db += (candidate - self.floor_db) * alpha(dt_ms, EnvelopeConfig::FLOOR_FALL_TC_MS);
        } else if !is_speech {
            self.floor_db += (candidate - self.floor_db) * alpha(dt_ms, EnvelopeConfig::FLOOR_RISE_TC_MS);
        }
        self.floor_db = self.floor_db.clamp(
            EnvelopeConfig::MINIMUM_NOISE_FLOOR_DB,
            EnvelopeConfig::MAXIMUM_NOISE_FLOOR_DB,
        );

        // Soft gate above the floor.
        let gate = smoothstep(
            self.floor_db + EnvelopeConfig::GATE_START_OFFSET_DB,
            self.floor_db + EnvelopeConfig::GATE_END_OFFSET_DB,
            db,
        );

        // Fixed dynamic-range map + response curve.
        let vis_min = (self.floor_db + EnvelopeConfig::VISUAL_MINIMUM_OFFSET_DB)
            .max(EnvelopeConfig::VISUAL_MINIMUM_FLOOR_DB);
        let vis_max = EnvelopeConfig::VISUAL_MAXIMUM_DB;
        let normalized = ((db - vis_min) / (vis_max - vis_min)).clamp(0.0, 1.0);
        let target = normalized.powf(EnvelopeConfig::RESPONSE_EXPONENT) * gate;

        // Time-normalized attack/release (frame-rate independent).
        let tc_ms = if target > self.smoothed { EnvelopeConfig::ATTACK_MS } else { EnvelopeConfig::RELEASE_MS };
        self.smoothed += (target - self.smoothed) * alpha(dt_ms, tc_ms);

        if self.smoothed < EnvelopeConfig::SILENCE_THRESHOLD { 0.0 } else { self.smoothed }
    }

    pub fn noise_floor_db(&self) -> f32 {
        self.floor_db
    }
}

fn alpha(dt_ms: f64, tc_ms: f64) -> f32 {
    (1.0 - (-dt_ms / tc_ms).exp()) as f32
}

fn smoothstep(edge0: f32, edge1: f32, x: f32) -> f32 {
    let t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
    t * t * (3.0 - 2.0 * t)
}

#[cfg(test)]
mod tests {
    use super::*;

    const FIXTURE: &str = include_str!("../../../../tests/fixtures/envelope-fixture.json");

    fn run(name: &str, p: &mut EnvelopeProcessor) -> Vec<f32> {
        let fixture: serde_json::Value = serde_json::from_str(FIXTURE).unwrap();
        let steps = fixture["scenarios"][name]
            .as_array()
            .unwrap_or_else(|| panic!("missing fixture scenario {name}"));
        let mut out = Vec::new();
        for step in steps {
            let dt = step["dtMs"].as_f64().unwrap() / 1000.0;
            let db = step["db"].as_f64().unwrap() as f32;
            for _ in 0..step["repeat"].as_u64().unwrap() {
                out.push(p.process(db, dt));
            }
        }
        out
    }

    // 1. 2 s of silence → output 0
    #[test]
    fn silence_is_zero() {
        let mut p = EnvelopeProcessor::new();
        let out = run("silence", &mut p);
        assert!(out.iter().rev().take(30).all(|&v| v == 0.0));
    }

    // 2. Input at the noise floor → ≤ 0.03
    #[test]
    fn noise_floor_suppressed() {
        let mut p = EnvelopeProcessor::new();
        let out = run("noiseFloor", &mut p);
        assert!(*out.last().unwrap() <= 0.03);
    }

    // 3. Speech −35..−18 dBFS → dynamic, roughly 0.30–0.90 with real spread
    #[test]
    fn speech_is_dynamic() {
        let soft = *run("speechSoft", &mut EnvelopeProcessor::new()).last().unwrap();
        let loud = *run("speechLoud", &mut EnvelopeProcessor::new()).last().unwrap();
        assert!(soft >= 0.30, "soft speech too low: {soft}");
        assert!(loud <= 0.90, "loud speech too high: {loud}");
        assert!(loud - soft >= 0.15, "soft vs loud not distinct: {soft} vs {loud}");
    }

    // 4. −8 dBFS → > 0.90, ≤ 1.0
    #[test]
    fn loud_near_max() {
        let out = *run("loud", &mut EnvelopeProcessor::new()).last().unwrap();
        assert!(out > 0.90 && out <= 1.0, "got {out}");
    }

    // 5. Silence → speech: ≥ 80% of steady value within ~70 ms
    #[test]
    fn attack() {
        let mut p = EnvelopeProcessor::new();
        run("attackSilence", &mut p);
        let early = *run("attackSpeechEarly", &mut p).last().unwrap();
        let steady = *run("attackSpeechSteady", &mut p).last().unwrap();
        assert!(early >= 0.8 * steady, "attack too slow: {early} vs steady {steady}");
    }

    // 6. Speech → silence: < 10% of steady value within ~550 ms
    #[test]
    fn release() {
        let mut p = EnvelopeProcessor::new();
        run("attackSilence", &mut p);
        let steady = *run("attackSpeechSteady", &mut p).last().unwrap();
        let released = *run("releaseSilence", &mut p).last().unwrap();
        assert!(released < 0.1 * steady, "release too slow: {released} vs steady {steady}");
    }

    // 7. 10 ms vs 33 ms update cadence → ~equal envelope after equal wall time
    #[test]
    fn frame_rate_independence() {
        let fine = *run("dtFine", &mut EnvelopeProcessor::new()).last().unwrap();
        let coarse = *run("dtCoarse", &mut EnvelopeProcessor::new()).last().unwrap();
        assert!((fine - coarse).abs() <= 0.05, "dt-dependent: {fine} vs {coarse}");
    }

    // 8. Extreme inputs → never NaN/Inf, always 0..1
    #[test]
    fn extremes_stay_finite() {
        let mut p = EnvelopeProcessor::new();
        for v in run("extremes", &mut p) {
            assert!(v.is_finite() && (0.0..=1.0).contains(&v), "got {v}");
        }
        assert!(p.process(f32::NAN, 0.033).is_finite());
        assert!(p.process(f32::INFINITY, 0.033).is_finite());
    }
}

pub struct SpectrumProcessor {
    pub bands: [f32; 7],
}

impl SpectrumProcessor {
    pub fn new() -> Self { Self { bands: [0.0; 7] } }

    pub fn process(&mut self, samples: &[f32], sample_rate: f64, dt: f64) -> [f32; 7] {
        if samples.is_empty() || sample_rate <= 0.0 { return self.bands; }
        let tau = std::f64::consts::TAU;
        for (index, frequency) in [125.0, 250.0, 500.0, 1000.0, 2000.0, 4000.0, 6000.0].iter().enumerate() {
            let mut power = 0.0_f64;
            for factor in [0.85, 1.0, 1.15] {
                if frequency * factor >= sample_rate / 2.0 { continue; }
                let coefficient = 2.0 * (tau * frequency * factor / sample_rate).cos();
                let (mut previous, mut before_previous) = (0.0, 0.0);
                for (i, value) in samples.iter().enumerate() {
                    let window = 0.5 - 0.5 * (tau * i as f64 / (samples.len() - 1).max(1) as f64).cos();
                    let sample = if value.is_finite() { *value as f64 } else { 0.0 };
                    let next = sample * window + coefficient * previous - before_previous;
                    before_previous = previous;
                    previous = next;
                }
                power = power.max(previous * previous + before_previous * before_previous - coefficient * previous * before_previous);
            }
            let amplitude = 4.0 * power.max(0.0).sqrt() / samples.len() as f64;
            let db = 20.0 * amplitude.max(1e-10).log10();
            let target = ((db + 60.0) / 48.0).clamp(0.0, 1.0).powf(0.8) as f32;
            let response = if target > self.bands[index] { 0.025 } else { 0.14 };
            self.bands[index] += (target - self.bands[index]) * (1.0 - (-dt.clamp(0.0, 0.25) / response).exp()) as f32;
        }
        self.bands
    }
}

#[cfg(test)]
mod spectrum_tests {
    use super::SpectrumProcessor;
    #[test]
    fn tones_drive_independent_bands_and_silence_settles() {
        let tone = |frequency: f64| (0..1024).map(|i| (0.1 * (std::f64::consts::TAU * frequency * i as f64 / 16000.0).sin()) as f32).collect::<Vec<_>>();
        let (mut low, mut high) = (SpectrumProcessor::new(), SpectrumProcessor::new());
        for _ in 0..15 { low.process(&tone(250.0), 16000.0, 1.0 / 30.0); high.process(&tone(4000.0), 16000.0, 1.0 / 30.0); }
        assert!(low.bands[1] > low.bands[5] + 0.3);
        assert!(high.bands[5] > high.bands[1] + 0.3);
        for _ in 0..60 { high.process(&[0.0; 1024], 16000.0, 1.0 / 30.0); }
        assert!(high.bands.iter().all(|x| *x < 0.001));
    }
}
