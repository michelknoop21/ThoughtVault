use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use cpal::Sample;
use hound::{SampleFormat as HoundSampleFormat, WavSpec, WavWriter};
use std::sync::{Arc, Mutex};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use tokio::sync::mpsc;
use super::envelope::{EnvelopeConfig, EnvelopeProcessor, SpectrumProcessor};
use super::types::{AudioDevice, RecordingCommand, RecordingEvent, RecordingMode};

const TARGET_SAMPLE_RATE: u32 = 16000;
const CHANNELS: u16 = 1;
const BITS_PER_SAMPLE: u16 = 16;

/// Streaming resampler that downsamples audio in chunks across callbacks.
/// Uses linear interpolation — sufficient quality for 48→16 kHz speech.
pub(crate) struct StreamingResampler {
    ratio: f64,           // from_rate / to_rate (e.g. 3.0 for 48→16)
    fractional_pos: f64,  // carried over between callbacks
}

impl StreamingResampler {
    pub(crate) fn new(from_rate: u32, to_rate: u32) -> Self {
        Self {
            ratio: from_rate as f64 / to_rate as f64,
            fractional_pos: 0.0,
        }
    }

    /// Returns true if resampling is needed (rates differ)
    fn is_active(&self) -> bool {
        (self.ratio - 1.0).abs() > 0.001
    }

    /// Resample a chunk of mono i16 samples. Returns resampled samples.
    pub(crate) fn process_i16(&mut self, input: &[i16]) -> Vec<i16> {
        if !self.is_active() { return input.to_vec(); }
        let mut output = Vec::new();
        while self.fractional_pos < input.len() as f64 {
            let idx = self.fractional_pos as usize;
            let frac = self.fractional_pos - idx as f64;
            let sample = if idx + 1 < input.len() {
                let s = input[idx] as f64 * (1.0 - frac) + input[idx + 1] as f64 * frac;
                s.round() as i16
            } else {
                input[idx]
            };
            output.push(sample);
            self.fractional_pos += self.ratio;
        }
        self.fractional_pos -= input.len() as f64;
        output
    }
}

/// Per-stream level meter: accumulates ~30 ms of mono samples, then runs
/// RMS → dBFS → shared envelope and returns the 0..1 scalar to emit (~30 Hz).
/// Owned by the audio callback closure — no shared state needed.
struct LevelMeter {
    samples: std::collections::VecDeque<f32>,
    sample_rate: u32,
    spectrum: SpectrumProcessor,
    sum_sq: f64,
    count: usize,
    window: usize,
    last_emit: std::time::Instant,
    processor: EnvelopeProcessor,
    last_log: std::time::Instant,
}

impl LevelMeter {
    fn new(sample_rate: u32) -> Self {
        let now = std::time::Instant::now();
        Self {
            samples: std::collections::VecDeque::new(),
            sample_rate,
            spectrum: SpectrumProcessor::new(),
            sum_sq: 0.0,
            count: 0,
            window: ((sample_rate as f64 / EnvelopeConfig::PUBLISH_RATE_HZ) as usize).max(1),
            last_emit: now,
            processor: EnvelopeProcessor::new(),
            last_log: now,
        }
    }

    fn push(&mut self, sample: f32) -> Option<(f32, [f32; 7])> {
        self.samples.push_back(sample);
        if self.samples.len() > (self.sample_rate as f64 * 0.064) as usize { self.samples.pop_front(); }
        self.sum_sq += (sample * sample) as f64;
        self.count += 1;
        if self.count < self.window {
            return None;
        }
        let rms = (self.sum_sq / self.count as f64).sqrt() as f32;
        let db = 20.0 * rms.max(1e-7).log10();
        let now = std::time::Instant::now();
        let dt = now.duration_since(self.last_emit).as_secs_f64();
        self.last_emit = now;
        self.sum_sq = 0.0;
        self.count = 0;
        let level = self.processor.process(db, dt);
        // Dev diagnostics every ~5 s (same fields as the macOS DEBUG overlay).
        if cfg!(debug_assertions) && now.duration_since(self.last_log).as_secs_f64() >= 5.0 {
            self.last_log = now;
            eprintln!("[Audio] Envelope — db={:.1} floor={:.1} out={:.3} dt={:.0}ms",
                db, self.processor.noise_floor_db(), level, dt * 1000.0);
        }
        let mut bands = self.spectrum.process(self.samples.make_contiguous(), self.sample_rate as f64, dt);
        if level == 0.0 { bands.fill(0.0); }
        Some((level, bands))
    }
}

pub fn get_devices() -> Vec<AudioDevice> {
    let host = cpal::default_host();
    let mut devices = Vec::new();

    let default_name = host
        .default_input_device()
        .and_then(|d| d.name().ok())
        .unwrap_or_default();

    if let Ok(inputs) = host.input_devices() {
        for device in inputs {
            if let Ok(name) = device.name() {
                devices.push(AudioDevice {
                    id: name.clone(),
                    name: name.clone(),
                    is_default: name == default_name,
                    is_input: true,
                });
            }
        }
    }

    devices
}

/// Spawn a recording session on a dedicated thread.
/// Returns the file path and a command sender.
pub fn start_recording_thread(
    device_id: Option<String>,
    mode: RecordingMode,
    output_path: String,
    event_tx: mpsc::UnboundedSender<RecordingEvent>,
) -> Result<(mpsc::Sender<RecordingCommand>, tokio::sync::oneshot::Receiver<Result<(), String>>), String> {
    let (ready_tx, ready_rx) = tokio::sync::oneshot::channel();
    let (cmd_tx, mut cmd_rx) = mpsc::channel::<RecordingCommand>(16);
    let output_path_clone = output_path.clone();

    // Capture a handle to the current Tokio runtime so the OS thread can
    // block_on async channel receives.
    let rt_handle = tokio::runtime::Handle::current();

    // cpal streams are !Send on some platforms, so we run everything on a
    // dedicated OS thread rather than a tokio task.
    std::thread::spawn(move || {
        let mut ready = Some(ready_tx);
        let result = recording_thread_body(
            device_id,
            mode,
            output_path_clone,
            &mut cmd_rx,
            &event_tx,
            &rt_handle,
            &mut ready,
        );
        if let Err(e) = result {
            if let Some(ready) = ready.take() { let _ = ready.send(Err(e.clone())); }
            let _ = event_tx.send(RecordingEvent::Error(e));
        }
    });

    Ok((cmd_tx, ready_rx))
}

fn recording_thread_body(
    device_id: Option<String>,
    mode: RecordingMode,
    output_path: String,
    cmd_rx: &mut mpsc::Receiver<RecordingCommand>,
    event_tx: &mpsc::UnboundedSender<RecordingEvent>,
    rt_handle: &tokio::runtime::Handle,
    ready: &mut Option<tokio::sync::oneshot::Sender<Result<(), String>>>,
) -> Result<(), String> {
    let host = cpal::default_host();

    // Select input device
    let input_device = if let Some(ref id) = device_id {
        host.input_devices()
            .ok()
            .and_then(|mut devs| devs.find(|d| d.name().map(|n| n == *id).unwrap_or(false)))
            .ok_or_else(|| format!("Audio apparaat '{}' niet gevonden", id))?
    } else {
        host.default_input_device()
            .ok_or("Geen standaard audio-invoerapparaat gevonden")?
    };

    // Probe the device for supported sample format - this is critical!
    // Most Windows devices support i16, not f32. We must build the stream
    // with a callback that matches the device's native format.
    let configs = input_device
        .supported_input_configs()
        .map_err(|e| format!("Kan audio configs niet lezen: {}", e))?;

    // Debug: log all available configs and collect them for later use
    eprintln!("[Audio] Available configs for device:");
    let configs_vec: Vec<_> = configs
        .map(|cfg| {
            eprintln!("  channels={:?}, min_rate={:?}, max_rate={:?}, format={:?}",
                cfg.channels(), cfg.min_sample_rate(), cfg.max_sample_rate(), cfg.sample_format());
            cfg
        })
        .collect();

    if configs_vec.is_empty() {
        return Err("Geen audio configuraties gevonden".to_string());
    }

    // Find a config that supports our requirements
    // Prefer TARGET_SAMPLE_RATE (16000), but fall back to any supported rate
    let supported = configs_vec
        .iter()
        .find(|c| c.channels() >= CHANNELS
            && c.min_sample_rate() <= cpal::SampleRate(TARGET_SAMPLE_RATE)
            && c.max_sample_rate() >= cpal::SampleRate(TARGET_SAMPLE_RATE))
        .or_else(|| {
            // Fall back to any config with enough channels, preferring higher sample rates
            eprintln!("[Audio] {} Hz niet beschikbaar, valt terug op alternatief", TARGET_SAMPLE_RATE);
            configs_vec.iter()
                .filter(|c| c.channels() >= CHANNELS)
                .max_by_key(|c| c.max_sample_rate())
        })
        .ok_or_else(|| {
            format!("Geen geschikte audio configuratie gevonden (zoekt: {} kanalen)", CHANNELS)
        })?;

    let sample_format = supported.sample_format();
    let device_channels = supported.channels();

    // Use the closest sample rate to TARGET, clamped to device's supported range
    let device_min = supported.min_sample_rate().0;
    let device_max = supported.max_sample_rate().0;
    let actual_sample_rate = TARGET_SAMPLE_RATE.clamp(device_min, device_max);

    eprintln!("[Audio] Mic: rate={} Hz (range: {}-{}), channels={}, format={:?}",
        actual_sample_rate, device_min, device_max, device_channels, sample_format);

    let config: cpal::StreamConfig = supported.clone()
        .with_sample_rate(cpal::SampleRate(actual_sample_rate))
        .into();

    // WAV spec ALWAYS at 16 kHz — resampling happens in the callback
    let wav_spec = WavSpec {
        channels: CHANNELS,
        sample_rate: TARGET_SAMPLE_RATE,
        bits_per_sample: BITS_PER_SAMPLE,
        sample_format: HoundSampleFormat::Int,
    };

    // Mic stream writes to the main output file
    let mic_writer = WavWriter::create(&output_path, wav_spec)
        .map_err(|e| format!("Kan opnamebestand niet aanmaken: {}", e))?;
    let mic_writer = Arc::new(Mutex::new(Some(mic_writer)));

    let is_paused = Arc::new(AtomicBool::new(false));

    // Track samples written for debugging
    let samples_written = Arc::new(AtomicU64::new(0));

    // Streaming resampler for mic: device rate → 16 kHz
    let mic_resampler = Arc::new(Mutex::new(StreamingResampler::new(actual_sample_rate, TARGET_SAMPLE_RATE)));
    if actual_sample_rate != TARGET_SAMPLE_RATE {
        eprintln!("[Audio] Mic resampler active: {} Hz → {} Hz (ratio {:.2})",
            actual_sample_rate, TARGET_SAMPLE_RATE, actual_sample_rate as f64 / TARGET_SAMPLE_RATE as f64);
    }

    eprintln!("[Audio] WAV file created: {} (sample rate: {} Hz)", output_path, TARGET_SAMPLE_RATE);

    // Build the appropriate input stream based on the device's sample format
    let input_stream = match sample_format {
        cpal::SampleFormat::I16 => build_input_stream_i16(
            &input_device, &config, actual_sample_rate, device_channels,
            Arc::clone(&mic_writer), Arc::clone(&is_paused),
            event_tx.clone(), Arc::clone(&samples_written),
            Arc::clone(&mic_resampler),
        )?,
        cpal::SampleFormat::F32 => build_input_stream_f32(
            &input_device, &config, actual_sample_rate, device_channels,
            Arc::clone(&mic_writer), Arc::clone(&is_paused),
            event_tx.clone(), Arc::clone(&samples_written),
            Arc::clone(&mic_resampler),
        )?,
        _ => return Err("Niet-ondersteunde sample format".to_string()),
    };

    // Optional loopback stream for combined mode (Windows WASAPI loopback).
    // Loopback writes to a SEPARATE file to avoid interleaved sample corruption.
    // After recording stops, both files are mixed together.
    let loopback_path = format!("{}.loopback.wav", output_path.trim_end_matches(".wav"));
    let loopback_writer: Arc<Mutex<Option<WavWriter<std::io::BufWriter<std::fs::File>>>>> =
        Arc::new(Mutex::new(None));
    let has_loopback;

    // Keep loopback stream alive until recording stops — underscore-prefixed
    // name creates a real binding (unlike bare `_` which drops immediately).
    let _loopback_stream: Option<Box<dyn StreamTrait>> = if mode == RecordingMode::Combined {
        #[cfg(target_os = "windows")]
        {
            match try_build_loopback_stream(
                &host, &loopback_path,
                Arc::clone(&loopback_writer), Arc::clone(&is_paused), event_tx.clone(),
            ) {
                Ok(stream) => {
                    eprintln!("[Audio] Loopback stream gestart voor systeemaudio opname");
                    has_loopback = true;
                    Some(Box::new(stream))
                },
                Err(e) => {
                    // A combined recording must never silently become mic-only.
                    // Clean up in case a file was partially created
                    *loopback_writer.lock().unwrap() = None;
                    let _ = std::fs::remove_file(&loopback_path);
                    return Err(format!("Systeemaudio niet beschikbaar: {e}. Kies Microfoon om alleen je microfoon op te nemen."));
                }
            }
        }
        #[cfg(not(target_os = "windows"))]
        {
            has_loopback = false;
            None
        }
    } else {
        has_loopback = false;
        None
    };

    input_stream.play().map_err(|e| format!("Kan stream niet starten: {}", e))?;
    if let Some(ready) = ready.take() { let _ = ready.send(Ok(())); }

    let start = std::time::Instant::now();

    // Block waiting for commands using the handle captured from the caller
    rt_handle.block_on(async {
        loop {
            match cmd_rx.recv().await {
                Some(RecordingCommand::Pause) => {
                    is_paused.store(true, Ordering::Relaxed);
                }
                Some(RecordingCommand::Resume) => {
                    is_paused.store(false, Ordering::Relaxed);
                }
                Some(RecordingCommand::Stop) | None => break,
            }
        }
    });

    let elapsed = start.elapsed().as_secs_f64();

    // Log samples written before finalize
    let total_samples = samples_written.load(Ordering::Relaxed);
    let duration = total_samples as f64 / TARGET_SAMPLE_RATE as f64;
    eprintln!("[Audio] Stopping recording: {} mono samples written ({:.2}s audio, {:.2}s elapsed)", total_samples, duration, elapsed);

    // Drop streams before finalizing writers
    drop(input_stream);
    drop(_loopback_stream);

    // Finalize mic WAV
    if let Ok(mut guard) = mic_writer.lock() {
        if let Some(w) = guard.take() {
            eprintln!("[Audio] Finalizing mic WAV file...");
            w.finalize().map_err(|e| format!("Microfoonopname opslaan mislukt: {e}"))?;
            eprintln!("[Audio] Mic WAV file finalized successfully");
        } else {
            eprintln!("[Audio] ERROR: mic writer was already None during finalize!");
        }
    } else {
        eprintln!("[Audio] ERROR: Failed to lock mic writer for finalize!");
    }

    // Finalize loopback WAV
    if has_loopback {
        if let Ok(mut guard) = loopback_writer.lock() {
            if let Some(w) = guard.take() {
                eprintln!("[Audio] Finalizing loopback WAV file...");
                w.finalize().map_err(|e| format!("Systeemaudio opslaan mislukt: {e}"))?;
                eprintln!("[Audio] Loopback WAV file finalized successfully");
            }
        }

        // Mix mic + loopback into the final output file
        eprintln!("[Audio] Mixing mic and loopback audio...");
        match mix_wav_files(&output_path, &loopback_path) {
            Ok(()) => {
                eprintln!("[Audio] Audio mixing completed successfully");
                let _ = std::fs::remove_file(&loopback_path);
            }
            Err(e) => {
                return Err(format!("Audio samenvoegen mislukt: {e}. De losse opnames zijn bewaard."));
            }
        }
    }

    let output_path_clone = output_path.clone();
    let _ = event_tx.send(RecordingEvent::Stopped {
        file_path: output_path_clone,
        duration_seconds: duration,
    });

    eprintln!("[Audio] Recording stopped, file: {}", output_path);

    Ok(())
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

/// Mix two WAV files using element-wise max (matches macOS mixAudioFiles approach).
/// The result overwrites the first file (mic_path).
/// Handles different sample rates by resampling the higher-rate stream.
fn mix_wav_files(mic_path: &str, loopback_path: &str) -> Result<(), String> {
    let mic_reader = hound::WavReader::open(mic_path)
        .map_err(|e| format!("Kan mic WAV niet lezen: {}", e))?;
    let loopback_reader = hound::WavReader::open(loopback_path)
        .map_err(|e| format!("Kan loopback WAV niet lezen: {}", e))?;

    let mic_spec = mic_reader.spec();
    let loopback_spec = loopback_reader.spec();

    eprintln!("[Audio] Mix specs — mic: {}Hz {}ch, loopback: {}Hz {}ch",
        mic_spec.sample_rate, mic_spec.channels, loopback_spec.sample_rate, loopback_spec.channels);

    let mic_samples: Vec<i16> = mic_reader.into_samples::<i16>()
        .filter_map(|s| s.ok())
        .collect();
    let loopback_samples: Vec<i16> = loopback_reader.into_samples::<i16>()
        .filter_map(|s| s.ok())
        .collect();

    // Resample to match mic's sample rate if needed
    let loopback_resampled = if loopback_spec.sample_rate != mic_spec.sample_rate {
        eprintln!("[Audio] Resampling loopback from {} Hz to {} Hz ({} samples)",
            loopback_spec.sample_rate, mic_spec.sample_rate, loopback_samples.len());
        let resampled = resample(&loopback_samples, loopback_spec.sample_rate, mic_spec.sample_rate);
        eprintln!("[Audio] Resampled to {} samples", resampled.len());
        resampled
    } else {
        loopback_samples
    };

    eprintln!("[Audio] Mixing: mic={} samples, loopback={} samples",
        mic_samples.len(), loopback_resampled.len());

    let max_len = mic_samples.len().max(loopback_resampled.len());
    let mut mixed = Vec::with_capacity(max_len);

    for i in 0..max_len {
        let mic_s = if i < mic_samples.len() { mic_samples[i] } else { 0 };
        let loopback_s = if i < loopback_resampled.len() { loopback_resampled[i] } else { 0 };
        // Element-wise max by absolute value — keeps whichever source is louder
        let mixed_s = if mic_s.unsigned_abs() >= loopback_s.unsigned_abs() { mic_s } else { loopback_s };
        mixed.push(mixed_s);
    }

    // Keep both sources intact until the complete mixed WAV is safely written.
    let parent = std::path::Path::new(mic_path).parent().ok_or("Opnamemap ontbreekt")?;
    let mut mixed_file = tempfile::NamedTempFile::new_in(parent)
        .map_err(|e| format!("Kan tijdelijk mixed WAV niet maken: {e}"))?;
    let mut writer = WavWriter::new(mixed_file.as_file_mut(), mic_spec)
        .map_err(|e| format!("Kan mixed WAV niet schrijven: {}", e))?;
    for sample in &mixed {
        writer.write_sample(*sample)
            .map_err(|e| format!("Fout bij schrijven mixed sample: {}", e))?;
    }
    writer.finalize()
        .map_err(|e| format!("Fout bij finaliseren mixed WAV: {}", e))?;
    mixed_file.persist(mic_path).map_err(|e| format!("Mixed WAV vervangen mislukt: {e}"))?;

    eprintln!("[Audio] Mixed output: {} samples", mixed.len());
    Ok(())
}

#[cfg(test)]
mod mix_tests {
    use super::*;

    #[test]
    fn mixed_file_keeps_system_audio_when_microphone_is_silent() {
        let dir = tempfile::tempdir().unwrap();
        let mic = dir.path().join("mic.wav");
        let system = dir.path().join("system.wav");
        let spec = WavSpec { channels: 1, sample_rate: 16000, bits_per_sample: 16, sample_format: HoundSampleFormat::Int };
        for (path, samples) in [(&mic, vec![0_i16, 0, 0]), (&system, vec![2000_i16, -4000, 1000])] {
            let mut writer = WavWriter::create(path, spec).unwrap();
            for sample in samples { writer.write_sample(sample).unwrap(); }
            writer.finalize().unwrap();
        }
        mix_wav_files(mic.to_str().unwrap(), system.to_str().unwrap()).unwrap();
        let mut reader = hound::WavReader::open(mic).unwrap();
        assert_eq!(reader.samples::<i16>().collect::<Result<Vec<_>, _>>().unwrap(), vec![2000, -4000, 1000]);
        assert!(system.is_file());
    }
}

/// Build an input stream for devices that output i16 samples (most Windows devices).
/// Performs stereo-to-mono downmix when channels > 1, then resamples to TARGET_SAMPLE_RATE.
fn build_input_stream_i16(
    device: &cpal::Device,
    config: &cpal::StreamConfig,
    sample_rate: u32,
    channels: u16,
    writer: Arc<Mutex<Option<WavWriter<std::io::BufWriter<std::fs::File>>>>>,
    is_paused: Arc<AtomicBool>,
    event_tx: mpsc::UnboundedSender<RecordingEvent>,
    samples_written: Arc<AtomicU64>,
    resampler: Arc<Mutex<StreamingResampler>>,
) -> Result<cpal::Stream, String> {
    let writer_clone = Arc::clone(&writer);
    let event_tx_clone = event_tx.clone();
    let samples_written_clone = Arc::clone(&samples_written);
    let resampler_clone = Arc::clone(&resampler);

    // Envelope meter (RMS → dBFS → shared envelope) owned by the callback
    let mut meter = LevelMeter::new(sample_rate);

    // Log first callback
    let first_callback = Arc::new(AtomicBool::new(true));
    let first_callback_clone = Arc::clone(&first_callback);

    eprintln!("[Audio] Building i16 input stream ({} channels)...", channels);

    let stream = device.build_input_stream(
        config,
        move |data: &[i16], _| {
            if first_callback_clone.swap(false, Ordering::Relaxed) {
                eprintln!("[Audio] FIRST CALLBACK: {} raw samples, {} channels → mono downmix + resample",
                    data.len(), channels);
            }

            if is_paused.load(Ordering::Relaxed) {
                return;
            }

            if let Ok(mut guard) = writer_clone.lock() {
                if let Some(ref mut w) = *guard {
                    let ch = channels as usize;
                    let frame_count = data.len() / ch;

                    // Step 1: Downmix to mono
                    let mut mono_chunk: Vec<i16> = Vec::with_capacity(frame_count);
                    for frame_idx in 0..frame_count {
                        let base = frame_idx * ch;
                        let mut sum: i32 = 0;
                        for c in 0..ch {
                            sum += data[base + c] as i32;
                        }
                        let mono_sample = (sum / channels as i32) as i16;
                        mono_chunk.push(mono_sample);

                        // Envelope on pre-resample samples, emitted at ~30 Hz
                        if let Some((level, bands)) = meter.push(mono_sample.to_float_sample()) {
                            let _ = event_tx_clone.send(RecordingEvent::AudioLevel(level));
                            let _ = event_tx_clone.send(RecordingEvent::AudioSpectrum(bands));
                        }
                    }

                    // Step 2: Resample chunk from device rate to 16 kHz
                    let resampled = if let Ok(mut r) = resampler_clone.lock() {
                        r.process_i16(&mono_chunk)
                    } else {
                        mono_chunk // fallback: write unresampled
                    };

                    // Step 3: Write resampled samples to WAV
                    for &sample in &resampled {
                        let _ = w.write_sample(sample);

                        let count = samples_written_clone.fetch_add(1, Ordering::Relaxed) + 1;
                        let count_usize = count as usize;

                        // Log every ~5 seconds (based on target rate)
                        if count_usize % (5 * TARGET_SAMPLE_RATE as usize) == 0 {
                            eprintln!("[Audio] Written {} mono samples (~{} seconds)",
                                count, count_usize / TARGET_SAMPLE_RATE as usize);
                        }
                    }
                } else {
                    eprintln!("[Audio] ERROR: writer is None in callback!");
                }
            } else {
                eprintln!("[Audio] ERROR: Failed to lock writer mutex in callback!");
            }
        },
        |err| eprintln!("[Audio] Stream error: {}", err),
        None,
    ).map_err(|e| format!("Kan i16 audio stream niet openen: {}", e))?;

    Ok(stream)
}

/// Build an input stream for devices that output f32 samples.
/// Performs stereo-to-mono downmix when channels > 1, then resamples to TARGET_SAMPLE_RATE.
fn build_input_stream_f32(
    device: &cpal::Device,
    config: &cpal::StreamConfig,
    sample_rate: u32,
    channels: u16,
    writer: Arc<Mutex<Option<WavWriter<std::io::BufWriter<std::fs::File>>>>>,
    is_paused: Arc<AtomicBool>,
    event_tx: mpsc::UnboundedSender<RecordingEvent>,
    samples_written: Arc<AtomicU64>,
    resampler: Arc<Mutex<StreamingResampler>>,
) -> Result<cpal::Stream, String> {
    let writer_clone = Arc::clone(&writer);
    let event_tx_clone = event_tx.clone();
    let samples_written_clone = Arc::clone(&samples_written);
    let resampler_clone = Arc::clone(&resampler);

    // Envelope meter (RMS → dBFS → shared envelope) owned by the callback
    let mut meter = LevelMeter::new(sample_rate);

    // Log first callback
    let first_callback = Arc::new(AtomicBool::new(true));
    let first_callback_clone = Arc::clone(&first_callback);

    eprintln!("[Audio] Building f32 input stream ({} channels)...", channels);

    let stream = device.build_input_stream(
        config,
        move |data: &[f32], _| {
            if first_callback_clone.swap(false, Ordering::Relaxed) {
                eprintln!("[Audio] FIRST CALLBACK (f32): {} raw samples, {} channels → mono downmix + resample",
                    data.len(), channels);
            }

            if is_paused.load(Ordering::Relaxed) {
                return;
            }

            if let Ok(mut guard) = writer_clone.lock() {
                if let Some(ref mut w) = *guard {
                    let ch = channels as usize;
                    let frame_count = data.len() / ch;

                    // Step 1: Downmix to mono and convert f32 → i16
                    let mut mono_chunk: Vec<i16> = Vec::with_capacity(frame_count);
                    for frame_idx in 0..frame_count {
                        let base = frame_idx * ch;
                        let mut sum: f32 = 0.0;
                        for c in 0..ch {
                            sum += data[base + c];
                        }
                        let mono_sample = sum / channels as f32;
                        let s16 = (mono_sample.clamp(-1.0, 1.0) * i16::MAX as f32) as i16;
                        mono_chunk.push(s16);

                        // Envelope on pre-resample samples, emitted at ~30 Hz
                        if let Some((level, bands)) = meter.push(mono_sample) {
                            let _ = event_tx_clone.send(RecordingEvent::AudioLevel(level));
                            let _ = event_tx_clone.send(RecordingEvent::AudioSpectrum(bands));
                        }
                    }

                    // Step 2: Resample chunk from device rate to 16 kHz
                    let resampled = if let Ok(mut r) = resampler_clone.lock() {
                        r.process_i16(&mono_chunk)
                    } else {
                        mono_chunk // fallback: write unresampled
                    };

                    // Step 3: Write resampled samples to WAV
                    for &sample in &resampled {
                        let _ = w.write_sample(sample);

                        let count = samples_written_clone.fetch_add(1, Ordering::Relaxed) + 1;
                        let count_usize = count as usize;

                        // Log every ~5 seconds (based on target rate)
                        if count_usize % (5 * TARGET_SAMPLE_RATE as usize) == 0 {
                            eprintln!("[Audio] Written {} mono samples (~{} seconds)",
                                count, count_usize / TARGET_SAMPLE_RATE as usize);
                        }
                    }
                } else {
                    eprintln!("[Audio] ERROR: writer is None in f32 callback!");
                }
            } else {
                eprintln!("[Audio] ERROR: Failed to lock writer mutex in f32 callback!");
            }
        },
        |err| eprintln!("[Audio] Stream error: {}", err),
        None,
    ).map_err(|e| format!("Kan f32 audio stream niet openen: {}", e))?;

    Ok(stream)
}

/// Build a WASAPI loopback capture stream on Windows.
/// Discovers the output device's native format, creates a WAV file at loopback_path
/// with the correct sample rate, and writes mono-downmixed audio.
#[cfg(target_os = "windows")]
fn try_build_loopback_stream(
    host: &cpal::Host,
    loopback_path: &str,
    writer: Arc<Mutex<Option<WavWriter<std::io::BufWriter<std::fs::File>>>>>,
    is_paused: Arc<AtomicBool>,
    event_tx: mpsc::UnboundedSender<RecordingEvent>,
) -> Result<cpal::Stream, String> {
    use cpal::traits::HostTrait;

    // On WASAPI: enumerate output devices — they support loopback capture
    let output_device = host.default_output_device()
        .ok_or("Geen standaard uitvoerapparaat voor loopback")?;

    let device_name = output_device.name().unwrap_or_else(|_| "unknown".to_string());
    eprintln!("[Audio] Loopback device: {}", device_name);

    // CRITICAL FIX: Use supported_output_configs() instead of supported_input_configs().
    // cpal returns empty from supported_input_configs() for output devices, but
    // build_input_stream() internally adds AUDCLNT_STREAMFLAGS_LOOPBACK for output devices.
    // We just need the correct format info from the output config query.
    let configs_vec: Vec<_> = output_device
        .supported_output_configs()
        .map_err(|e| format!("Kan loopback configs niet lezen: {}", e))?
        .map(|cfg| {
            eprintln!("[Audio] Loopback config: channels={}, rate={}-{}, format={:?}",
                cfg.channels(), cfg.min_sample_rate().0, cfg.max_sample_rate().0, cfg.sample_format());
            cfg
        })
        .collect();

    if configs_vec.is_empty() {
        return Err("Geen loopback configuraties gevonden (supported_output_configs leeg)".to_string());
    }

    // Find a config — prefer one that includes our target rate, otherwise use highest available
    let supported = configs_vec
        .iter()
        .find(|c| c.channels() >= CHANNELS
            && c.min_sample_rate() <= cpal::SampleRate(TARGET_SAMPLE_RATE)
            && c.max_sample_rate() >= cpal::SampleRate(TARGET_SAMPLE_RATE))
        .or_else(|| {
            eprintln!("[Audio] Loopback: {} Hz niet beschikbaar, zoekt alternatief", TARGET_SAMPLE_RATE);
            configs_vec.iter()
                .filter(|c| c.channels() >= CHANNELS)
                .max_by_key(|c| c.max_sample_rate())
        })
        .ok_or("Geen geschikte loopback configuratie gevonden")?;

    let sample_format = supported.sample_format();
    let loopback_channels = supported.channels();

    // Use the closest sample rate to TARGET, clamped to device's supported range
    let device_min = supported.min_sample_rate().0;
    let device_max = supported.max_sample_rate().0;
    let loopback_rate = TARGET_SAMPLE_RATE.clamp(device_min, device_max);

    eprintln!("[Audio] Loopback: rate={} Hz (range: {}-{}), channels={}, format={:?}",
        loopback_rate, device_min, device_max, loopback_channels, sample_format);

    let config: cpal::StreamConfig = supported.clone()
        .with_sample_rate(cpal::SampleRate(loopback_rate))
        .into();

    // Loopback WAV ALWAYS at 16 kHz — resampling happens in the callback
    let loopback_wav_spec = WavSpec {
        channels: CHANNELS,
        sample_rate: TARGET_SAMPLE_RATE,
        bits_per_sample: BITS_PER_SAMPLE,
        sample_format: HoundSampleFormat::Int,
    };

    let loopback_writer = WavWriter::create(loopback_path, loopback_wav_spec)
        .map_err(|e| format!("Kan loopback WAV niet aanmaken: {}", e))?;
    *writer.lock().unwrap() = Some(loopback_writer);

    // Streaming resampler for loopback: device rate → 16 kHz
    let loopback_resampler = Arc::new(Mutex::new(StreamingResampler::new(loopback_rate, TARGET_SAMPLE_RATE)));
    if loopback_rate != TARGET_SAMPLE_RATE {
        eprintln!("[Audio] Loopback resampler active: {} Hz → {} Hz (ratio {:.2})",
            loopback_rate, TARGET_SAMPLE_RATE, loopback_rate as f64 / TARGET_SAMPLE_RATE as f64);
    }

    // Loopback needs format-specific handling with stereo-to-mono downmix + resample
    match sample_format {
        cpal::SampleFormat::I16 => {
            let writer_clone = Arc::clone(&writer);
            let resampler_clone = Arc::clone(&loopback_resampler);
            let mut meter = LevelMeter::new(loopback_rate);
            let levels_tx = event_tx.clone();

            // Log first callback once
            let first_callback = Arc::new(AtomicBool::new(true));
            let first_callback_clone = Arc::clone(&first_callback);

            let stream = output_device.build_input_stream(
                &config,
                move |data: &[i16], _| {
                    if first_callback_clone.swap(false, Ordering::Relaxed) {
                        eprintln!("[Audio] Loopback FIRST CALLBACK: {} raw samples, {} channels → mono downmix + resample",
                            data.len(), loopback_channels);
                    }

                    if is_paused.load(Ordering::Relaxed) {
                        return;
                    }
                    if let Ok(mut guard) = writer_clone.lock() {
                        if let Some(ref mut w) = &mut *guard {
                            let ch = loopback_channels as usize;
                            let frame_count = data.len() / ch;

                            // Downmix, meter system audio, then resample for storage.
                            let mut mono_chunk: Vec<i16> = Vec::with_capacity(frame_count);
                            for frame_idx in 0..frame_count {
                                let base = frame_idx * ch;
                                let mut sum: i32 = 0;
                                for c in 0..ch {
                                    sum += data[base + c] as i32;
                                }
                                let mono = (sum / loopback_channels as i32) as i16;
                                mono_chunk.push(mono);
                                if let Some((level, bands)) = meter.push(mono.to_float_sample()) {
                                    let _ = levels_tx.send(RecordingEvent::SystemAudioLevel(level));
                                    let _ = levels_tx.send(RecordingEvent::SystemAudioSpectrum(bands));
                                }
                            }

                            // Step 2: Resample chunk from device rate to 16 kHz
                            let resampled = if let Ok(mut r) = resampler_clone.lock() {
                                r.process_i16(&mono_chunk)
                            } else {
                                mono_chunk
                            };

                            // Step 3: Write resampled samples to WAV
                            for &sample in &resampled {
                                let _ = w.write_sample(sample);
                            }
                        }
                    }
                },
                |err| eprintln!("[Audio] Loopback stream error: {}", err),
                None,
            ).map_err(|e| format!("Loopback i16 stream fout: {}", e))?;
            stream.play().map_err(|e| format!("Kan loopback stream niet starten: {}", e))?;
            Ok(stream)
        }
        cpal::SampleFormat::F32 => {
            let writer_clone = Arc::clone(&writer);
            let resampler_clone = Arc::clone(&loopback_resampler);
            let mut meter = LevelMeter::new(loopback_rate);
            let levels_tx = event_tx.clone();

            // Log first callback once
            let first_callback = Arc::new(AtomicBool::new(true));
            let first_callback_clone = Arc::clone(&first_callback);

            let stream = output_device.build_input_stream(
                &config,
                move |data: &[f32], _| {
                    if first_callback_clone.swap(false, Ordering::Relaxed) {
                        eprintln!("[Audio] Loopback FIRST CALLBACK (f32): {} raw samples, {} channels → mono downmix + resample",
                            data.len(), loopback_channels);
                    }

                    if is_paused.load(Ordering::Relaxed) {
                        return;
                    }
                    if let Ok(mut guard) = writer_clone.lock() {
                        if let Some(ref mut w) = &mut *guard {
                            let ch = loopback_channels as usize;
                            let frame_count = data.len() / ch;

                            // Step 1: Downmix to mono and convert f32 → i16
                            let mut mono_chunk: Vec<i16> = Vec::with_capacity(frame_count);
                            for frame_idx in 0..frame_count {
                                let base = frame_idx * ch;
                                let mut sum: f32 = 0.0;
                                for c in 0..ch {
                                    sum += data[base + c];
                                }
                                let mono_sample = sum / loopback_channels as f32;
                                mono_chunk.push((mono_sample.clamp(-1.0, 1.0) * i16::MAX as f32) as i16);
                                if let Some((level, bands)) = meter.push(mono_sample) {
                                    let _ = levels_tx.send(RecordingEvent::SystemAudioLevel(level));
                                    let _ = levels_tx.send(RecordingEvent::SystemAudioSpectrum(bands));
                                }
                            }

                            // Step 2: Resample chunk from device rate to 16 kHz
                            let resampled = if let Ok(mut r) = resampler_clone.lock() {
                                r.process_i16(&mono_chunk)
                            } else {
                                mono_chunk
                            };

                            // Step 3: Write resampled samples to WAV
                            for &sample in &resampled {
                                let _ = w.write_sample(sample);
                            }
                        }
                    }
                },
                |err| eprintln!("[Audio] Loopback stream error: {}", err),
                None,
            ).map_err(|e| format!("Loopback f32 stream fout: {}", e))?;
            stream.play().map_err(|e| format!("Kan loopback stream niet starten: {}", e))?;
            Ok(stream)
        }
        _ => Err("Niet-ondersteunde loopback sample format".to_string()),
    }
}
