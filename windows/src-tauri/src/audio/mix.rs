//! Mixes the microphone and system recordings into one mono WAV.
//! Same rule as `AudioMixer.mix` on macOS: each source is first brought to the same speech
//! level, then the two are summed and clamped. The capture levels differ per microphone and
//! per call app, and halving the sum cost another 6 dB.

use hound::WavWriter;

/// Target for the loud speech blocks of a source, about -21 dBFS RMS.
const TARGET_LEVEL: f32 = 0.09;

/// Gain that brings a source with this speech level to the target. A source without signal
/// keeps gain 1, and the range is capped so noise is not blown up and a hot source is not crushed.
fn gain_for_level(level: f32) -> f32 {
    if level < 0.001 { 1.0 } else { (TARGET_LEVEL / level).clamp(0.25, 16.0) }
}

/// Speech level of one source (0..1): the 95th percentile of the RMS per 100 ms block. A percentile
/// ignores the silence between turns and a single loud click, which a peak or a mean would not.
fn speech_level(path: &str) -> Result<f32, String> {
    let reader = hound::WavReader::open(path).map_err(|e| format!("Kan WAV niet lezen: {e}"))?;
    let block = (reader.spec().sample_rate / 10).max(1) as usize;
    let mut blocks = Vec::new();
    let (mut sum, mut count) = (0.0_f64, 0_usize);
    for sample in reader.into_samples::<i16>() {
        let value = f64::from(sample.map_err(|e| format!("Audio lezen mislukt: {e}"))?) / 32768.0;
        sum += value * value;
        count += 1;
        if count == block {
            blocks.push((sum / count as f64).sqrt() as f32);
            (sum, count) = (0.0, 0);
        }
    }
    if count > 0 { blocks.push((sum / count as f64).sqrt() as f32); }
    if blocks.is_empty() { return Ok(0.0); }
    blocks.sort_by(f32::total_cmp);
    Ok(blocks[(0.95 * (blocks.len() - 1) as f32) as usize])
}

/// Resample audio using linear interpolation.
fn resample(samples: &[i16], from_rate: u32, to_rate: u32) -> Vec<i16> {
    if from_rate == to_rate || samples.is_empty() {
        return samples.to_vec();
    }
    let ratio = from_rate as f64 / to_rate as f64;
    let new_len = (samples.len() as f64 / ratio).ceil() as usize;
    let mut result = Vec::with_capacity(new_len);
    for i in 0..new_len {
        let src_pos = i as f64 * ratio;
        let idx = src_pos as usize;
        let frac = src_pos - idx as f64;
        if idx + 1 < samples.len() {
            let s = samples[idx] as f64 * (1.0 - frac) + samples[idx + 1] as f64 * frac;
            result.push(s.round() as i16);
        } else if idx < samples.len() {
            result.push(samples[idx]);
        }
    }
    result
}

/// Mix two WAV files; the result overwrites the first file (mic_path).
/// Handles different sample rates by resampling the higher-rate stream.
pub(super) fn mix_wav_files(mic_path: &str, loopback_path: &str) -> Result<(), String> {
    let mic_gain = gain_for_level(speech_level(mic_path)?);
    let system_gain = gain_for_level(speech_level(loopback_path)?);

    let mic_reader = hound::WavReader::open(mic_path)
        .map_err(|e| format!("Kan mic WAV niet lezen: {}", e))?;
    let loopback_reader = hound::WavReader::open(loopback_path)
        .map_err(|e| format!("Kan loopback WAV niet lezen: {}", e))?;

    let mic_spec = mic_reader.spec();
    let loopback_spec = loopback_reader.spec();

    elog!("[Audio] Mix specs — mic: {}Hz {}ch gain {:.2}, loopback: {}Hz {}ch gain {:.2}",
        mic_spec.sample_rate, mic_spec.channels, mic_gain, loopback_spec.sample_rate, loopback_spec.channels, system_gain);

    let mut mic_samples = mic_reader.into_samples::<i16>();
    // Native recordings are both 16 kHz; stream them instead of allocating
    // three complete recordings in memory when a multi-hour meeting stops.
    let mut system_samples: Box<dyn Iterator<Item = Result<i16, hound::Error>>> =
        if loopback_spec.sample_rate == mic_spec.sample_rate {
            Box::new(loopback_reader.into_samples::<i16>())
        } else {
            let samples = loopback_reader.into_samples::<i16>()
                .collect::<Result<Vec<_>, _>>()
                .map_err(|e| format!("Systeemaudio lezen mislukt: {e}"))?;
            Box::new(resample(&samples, loopback_spec.sample_rate, mic_spec.sample_rate)
                .into_iter().map(Ok))
        };

    // Keep both sources intact until the complete mixed WAV is safely written.
    let parent = std::path::Path::new(mic_path).parent().ok_or("Opnamemap ontbreekt")?;
    let mut mixed_file = tempfile::NamedTempFile::new_in(parent)
        .map_err(|e| format!("Kan tijdelijk mixed WAV niet maken: {e}"))?;
    let mut writer = WavWriter::new(std::io::BufWriter::new(mixed_file.as_file_mut()), mic_spec)
        .map_err(|e| format!("Kan mixed WAV niet schrijven: {}", e))?;
    let mut count = 0_u64;
    loop {
        let mic = mic_samples.next().transpose()
            .map_err(|e| format!("Microfoonaudio lezen mislukt: {e}"))?;
        let system = system_samples.next().transpose()
            .map_err(|e| format!("Systeemaudio lezen mislukt: {e}"))?;
        if mic.is_none() && system.is_none() { break; }
        let mic = mic.unwrap_or(0);
        let system = system.unwrap_or(0);
        let mixed = (f32::from(mic) * mic_gain + f32::from(system) * system_gain)
            .round().clamp(f32::from(i16::MIN), f32::from(i16::MAX)) as i16;
        writer.write_sample(mixed)
            .map_err(|e| format!("Fout bij schrijven mixed sample: {e}"))?;
        count += 1;
    }
    writer.finalize()
        .map_err(|e| format!("Fout bij finaliseren mixed WAV: {}", e))?;
    // Windows cannot replace the destination while its reader handle is open.
    drop(mic_samples);
    drop(system_samples);
    mixed_file.persist(mic_path).map_err(|e| format!("Mixed WAV vervangen mislukt: {e}"))?;

    elog!("[Audio] Mixed output: {} samples", count);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use hound::{SampleFormat, WavSpec};

    const RATE: u32 = 16000;

    /// Writes mic and system from (frames, value) segments, mixes, and returns the mixed samples.
    fn mix(mic: &[(u32, i16)], system: &[(u32, i16)], system_rate: u32) -> Vec<i16> {
        let dir = tempfile::tempdir().unwrap();
        let (mic_path, system_path) = (dir.path().join("mic.wav"), dir.path().join("system.wav"));
        for (path, rate, segments) in [(&mic_path, RATE, mic), (&system_path, system_rate, system)] {
            let spec = WavSpec { channels: 1, sample_rate: rate, bits_per_sample: 16, sample_format: SampleFormat::Int };
            let mut writer = WavWriter::create(path, spec).unwrap();
            for &(frames, value) in segments {
                for _ in 0..frames { writer.write_sample(value).unwrap(); }
            }
            writer.finalize().unwrap();
        }
        mix_wav_files(mic_path.to_str().unwrap(), system_path.to_str().unwrap()).unwrap();
        assert!(system_path.is_file());
        hound::WavReader::open(mic_path).unwrap().into_samples::<i16>().collect::<Result<Vec<_>, _>>().unwrap()
    }

    fn near(actual: i16, expected: i16) { assert!((actual - expected).abs() <= 2, "{actual} is not near {expected}"); }

    #[test]
    fn both_sources_are_levelled_then_summed() {
        // 0.3 and 0.02 of full scale each land on 0.09, so the sum is 0.18.
        let mixed = mix(&[(RATE, 9830)], &[(RATE, 655)], RATE);
        assert_eq!(mixed.len(), RATE as usize);
        near(mixed[100], 5898);
    }

    #[test]
    fn quiet_source_is_raised_and_silent_source_left_alone() {
        near(mix(&[(RATE, 328)], &[(RATE, 0)], RATE)[100], 2949);
    }

    #[test]
    fn gain_is_capped() {
        assert_eq!(gain_for_level(0.002), 16.0);
        assert_eq!(gain_for_level(1.0), 0.25);
        assert_eq!(gain_for_level(0.0005), 1.0);
    }

    #[test]
    fn loud_click_does_not_set_the_level_and_is_clamped() {
        // 20 blocks at 0.05 and one at full scale: the level stays 0.05, so the gain is 1.8.
        let high = mix(&[(2 * RATE, 1638), (1600, i16::MAX)], &[(RATE, 0)], RATE);
        near(high[100], 2949);
        assert_eq!(high[2 * RATE as usize + 100], i16::MAX);
        let low = mix(&[(2 * RATE, -1638), (1600, i16::MIN)], &[(RATE, 0)], RATE);
        assert_eq!(low[2 * RATE as usize + 100], i16::MIN);
    }

    #[test]
    fn opposing_samples_cancel_and_the_longer_source_keeps_its_tail() {
        // Below the level threshold both gains are 1, so the sum is exact.
        for system_rate in [RATE, 2 * RATE] {
            let system: &[(u32, i16)] = if system_rate == RATE { &[(1, 20), (1, -2), (1, 3)] }
                else { &[(1, 20), (1, 0), (1, -2), (1, 0), (1, 3), (1, 0)] };
            assert_eq!(mix(&[(1, -20), (1, 1)], system, system_rate), vec![0, -1, 3]);
        }
    }

    #[test]
    #[ignore = "creates three hours of PCM to verify long-meeting processing"]
    fn three_hour_mix_preserves_duration_and_timed_markers() {
        let dir = tempfile::tempdir().unwrap();
        let mic = dir.path().join("mic.wav");
        let system = dir.path().join("system.wav");
        let total = 3 * 60 * 60 * RATE;
        let markers = [17 * RATE, total / 2, total - RATE];
        let spec = WavSpec { channels: 1, sample_rate: RATE, bits_per_sample: 16, sample_format: SampleFormat::Int };
        for (path, is_system) in [(&mic, false), (&system, true)] {
            let mut writer = WavWriter::create(path, spec).unwrap();
            for index in 0..total {
                let sample: i16 = if markers.contains(&index) { if is_system { -2000 } else { 1000 } } else { 0 };
                writer.write_sample(sample).unwrap();
            }
            writer.finalize().unwrap();
        }
        mix_wav_files(mic.to_str().unwrap(), system.to_str().unwrap()).unwrap();
        let mut reader = hound::WavReader::open(&mic).unwrap();
        assert_eq!(reader.duration(), total);
        for marker in markers {
            reader.seek(marker - 1).unwrap();
            let samples = reader.samples::<i16>().take(3).collect::<Result<Vec<_>, _>>().unwrap();
            // Single-sample markers leave the level at zero, so both gains stay 1.
            assert_eq!(samples, [0, -1000, 0]);
        }
        assert!(system.is_file());
    }
}
