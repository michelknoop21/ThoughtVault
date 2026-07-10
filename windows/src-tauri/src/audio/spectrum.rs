// spectrum.rs
// Lightweight FFT analysis for the pitch-responsive waveform. The recorder only
// exposes an RMS level; this derives per-band magnitudes + a spectral centroid
// so low voices render as broad slow waves and high tones as tight fast ones.

use std::sync::Arc;

use rustfft::{num_complex::Complex, Fft, FftPlanner};

pub const BAND_COUNT: usize = 5;
const FFT_SIZE: usize = 1024;
const LOW_HZ: f32 = 80.0;
const HIGH_HZ: f32 = 6000.0;

/// Rolling analyzer: push mono samples (-1.0..1.0); every FFT_SIZE samples it
/// computes a new spectrum snapshot available via `latest()`.
pub struct SpectrumAnalyzer {
    fft: Arc<dyn Fft<f32>>,
    window: Vec<f32>,
    buf: Vec<f32>,
    sample_rate: f32,
    latest_bands: [f32; BAND_COUNT],
    latest_centroid: f32,
}

impl SpectrumAnalyzer {
    pub fn new(sample_rate: f32) -> Self {
        let fft = FftPlanner::<f32>::new().plan_fft_forward(FFT_SIZE);
        // Hann window.
        let window: Vec<f32> = (0..FFT_SIZE)
            .map(|n| {
                let x = std::f32::consts::PI * n as f32 / (FFT_SIZE as f32 - 1.0);
                x.sin().powi(2)
            })
            .collect();
        Self {
            fft,
            window,
            buf: Vec::with_capacity(FFT_SIZE),
            sample_rate,
            latest_bands: [0.0; BAND_COUNT],
            latest_centroid: 0.5,
        }
    }

    pub fn push(&mut self, sample: f32) {
        self.buf.push(sample);
        if self.buf.len() >= FFT_SIZE {
            self.compute();
            self.buf.clear();
        }
    }

    pub fn latest(&self) -> (Vec<f32>, f32) {
        (self.latest_bands.to_vec(), self.latest_centroid)
    }

    fn compute(&mut self) {
        let mut data: Vec<Complex<f32>> = (0..FFT_SIZE)
            .map(|i| Complex::new(self.buf[i] * self.window[i], 0.0))
            .collect();
        self.fft.process(&mut data);

        let half = FFT_SIZE / 2;
        let nyquist = self.sample_rate / 2.0;
        let bin_hz = nyquist / half as f32;

        // Log-spaced band edges across the speech range.
        let mut edges = [0.0f32; BAND_COUNT + 1];
        for (i, e) in edges.iter_mut().enumerate() {
            let t = i as f32 / BAND_COUNT as f32;
            *e = LOW_HZ * (HIGH_HZ / LOW_HZ).powf(t);
        }

        let mut bands = [0.0f32; BAND_COUNT];
        let mut centroid_num = 0.0f32;
        let mut centroid_den = 0.0f32;
        for b in 0..BAND_COUNT {
            let start = ((edges[b] / bin_hz) as usize).max(1);
            let end = ((edges[b + 1] / bin_hz) as usize).min(half - 1);
            if end < start {
                continue;
            }
            let mut sum = 0.0f32;
            for bin in start..=end {
                let amp = data[bin].norm();
                sum += amp;
                centroid_num += amp * (bin as f32 * bin_hz);
                centroid_den += amp;
            }
            let mean = sum / (end - start + 1) as f32;
            // Compress tiny FFT amplitudes to a visible 0..1 range.
            bands[b] = (1.0 + mean * 40.0).log10().min(1.0);
        }

        let mut norm_centroid = 0.5;
        if centroid_den > 0.0 {
            let c_hz = (centroid_num / centroid_den).clamp(LOW_HZ, HIGH_HZ);
            norm_centroid = (c_hz / LOW_HZ).ln() / (HIGH_HZ / LOW_HZ).ln();
        }

        // Light smoothing.
        for b in 0..BAND_COUNT {
            self.latest_bands[b] += (bands[b] - self.latest_bands[b]) * 0.5;
        }
        self.latest_centroid += (norm_centroid - self.latest_centroid) * 0.3;
    }
}
