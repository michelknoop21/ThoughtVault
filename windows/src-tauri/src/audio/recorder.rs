use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use cpal::Sample;
use hound::{SampleFormat as HoundSampleFormat, WavSpec, WavWriter};
use std::sync::{Arc, Mutex};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use tokio::sync::mpsc;
use super::envelope::{EnvelopeConfig, EnvelopeProcessor, SpectrumProcessor};
use super::types::{AudioDevice, RecordingCommand, RecordingEvent, RecordingMode, RecordingResult};

const TARGET_SAMPLE_RATE: u32 = 16000;
const CHANNELS: u16 = 1;
const BITS_PER_SAMPLE: u16 = 16;

// Both sources use the same active clock; WASAPI omits packets during silence.
struct CaptureClock {
    started: std::time::Instant,
    paused_at: Option<std::time::Instant>,
    paused: std::time::Duration,
}

impl CaptureClock {
    fn position(&self, info: &cpal::InputCallbackInfo) -> u64 {
        let timestamp = info.timestamp();
        let latency = timestamp.callback.duration_since(&timestamp.capture).unwrap_or_default();
        let elapsed = self.started.elapsed().saturating_sub(self.paused).saturating_sub(latency);
        (elapsed.as_secs_f64() * TARGET_SAMPLE_RATE as f64).round() as u64
    }
}

fn write_timed_chunk<W: std::io::Write + std::io::Seek>(
    writer: &mut WavWriter<W>, samples: &[i16], position: u64, written: &mut u64,
) -> Result<(), hound::Error> {
    // Ignore sub-20ms callback jitter, but preserve actual gaps and trim late packets.
    let tolerance = u64::from(TARGET_SAMPLE_RATE / 50);
    if position > written.saturating_add(tolerance) {
        while *written < position {
            writer.write_sample(0_i16)?;
            *written += 1;
        }
    }
    let overlap = written.saturating_sub(position);
    let skip = if overlap > tolerance { overlap.min(samples.len() as u64) as usize } else { 0 };
    for &sample in &samples[skip..] {
        writer.write_sample(sample)?;
        *written += 1;
    }
    Ok(())
}

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
    done_tx: tokio::sync::oneshot::Sender<Result<RecordingResult, String>>,
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
        let _ = done_tx.send(result.clone());
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
) -> Result<RecordingResult, String> {
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
    let clock = Arc::new(Mutex::new(CaptureClock {
        started: std::time::Instant::now(), paused_at: None, paused: std::time::Duration::ZERO,
    }));

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
            Arc::clone(&mic_writer), Arc::clone(&is_paused), Arc::clone(&clock),
            event_tx.clone(), Arc::clone(&samples_written),
            Arc::clone(&mic_resampler),
        )?,
        cpal::SampleFormat::F32 => build_input_stream_f32(
            &input_device, &config, actual_sample_rate, device_channels,
            Arc::clone(&mic_writer), Arc::clone(&is_paused), Arc::clone(&clock),
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
                Arc::clone(&loopback_writer), Arc::clone(&is_paused), Arc::clone(&clock), event_tx.clone(),
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
                    let mut clock = clock.lock().unwrap();
                    if clock.paused_at.is_none() { clock.paused_at = Some(std::time::Instant::now()); }
                }
                Some(RecordingCommand::Resume) => {
                    let mut clock = clock.lock().unwrap();
                    if let Some(paused_at) = clock.paused_at.take() { clock.paused += paused_at.elapsed(); }
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

    Ok(RecordingResult { file_path: output_path, duration_seconds: duration })
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
        let mixed = if mic.unsigned_abs() >= system.unsigned_abs() { mic } else { system };
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

    eprintln!("[Audio] Mixed output: {} samples", count);
    Ok(())
}

#[cfg(test)]
mod mix_tests {
    use super::*;

    #[tokio::test]
    async fn completion_does_not_depend_on_draining_visual_events() {
        let (events, _unread_events) = mpsc::unbounded_channel();
        let (done, result) = tokio::sync::oneshot::channel();
        let (_commands, ready) = start_recording_thread(
            Some("ThoughtVault QA missing device".into()), RecordingMode::Microphone,
            "unused-qa-recording.wav".into(), events, done,
        ).unwrap();
        assert!(ready.await.unwrap().is_err());
        let result = tokio::time::timeout(std::time::Duration::from_secs(5), result).await.unwrap().unwrap();
        assert!(result.unwrap_err().contains("niet gevonden"));
    }

    #[test]
    fn timed_chunks_preserve_silence_and_do_not_duplicate_late_packets() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("timeline.wav");
        let spec = WavSpec { channels: 1, sample_rate: TARGET_SAMPLE_RATE, bits_per_sample: 16, sample_format: HoundSampleFormat::Int };
        let mut writer = WavWriter::create(&path, spec).unwrap();
        let mut written = 0;
        write_timed_chunk(&mut writer, &[12, -34], 16000, &mut written).unwrap();
        write_timed_chunk(&mut writer, &[56, -78], 32000, &mut written).unwrap();
        write_timed_chunk(&mut writer, &[999; 400], 16000, &mut written).unwrap();
        assert_eq!(written, 32002);
        writer.finalize().unwrap();
        let samples = hound::WavReader::open(path).unwrap().into_samples::<i16>().collect::<Result<Vec<_>, _>>().unwrap();
        assert!(samples[..16000].iter().all(|&sample| sample == 0));
        assert_eq!(&samples[16000..16002], &[12, -34]);
        assert!(samples[16002..32000].iter().all(|&sample| sample == 0));
        assert_eq!(&samples[32000..], &[56, -78]);
    }

    #[test]
    fn timed_chunks_tolerate_callback_jitter_without_growing_silence() {
        let mut writer = WavWriter::new(std::io::Cursor::new(Vec::new()), WavSpec {
            channels: 1, sample_rate: TARGET_SAMPLE_RATE, bits_per_sample: 16, sample_format: HoundSampleFormat::Int,
        }).unwrap();
        let mut written = 0;
        for position in [0, 180, 300, 500] {
            write_timed_chunk(&mut writer, &[1; 160], position, &mut written).unwrap();
        }
        assert_eq!(written, 640);
    }

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

    #[test]
    fn streamed_mix_preserves_extremes_tails_and_resampling() {
        let dir = tempfile::tempdir().unwrap();
        let mic = dir.path().join("mic.wav");
        let system = dir.path().join("system.wav");
        for system_rate in [16000, 32000] {
            for (path, rate, samples) in [
                (&mic, 16000, vec![i16::MIN, 1]),
                (&system, system_rate, if system_rate == 16000 {
                    vec![i16::MAX, -2, 3]
                } else { vec![i16::MAX, 0, -2, 0, 3, 0] }),
            ] {
                let spec = WavSpec { channels: 1, sample_rate: rate, bits_per_sample: 16, sample_format: HoundSampleFormat::Int };
                let mut writer = WavWriter::create(path, spec).unwrap();
                for sample in samples { writer.write_sample(sample).unwrap(); }
                writer.finalize().unwrap();
            }
            mix_wav_files(mic.to_str().unwrap(), system.to_str().unwrap()).unwrap();
            let samples = hound::WavReader::open(&mic).unwrap().into_samples::<i16>()
                .collect::<Result<Vec<_>, _>>().unwrap();
            assert_eq!(samples, vec![i16::MIN, -2, 3]);
            assert!(system.is_file());
        }
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
    clock: Arc<Mutex<CaptureClock>>,
    event_tx: mpsc::UnboundedSender<RecordingEvent>,
    samples_written: Arc<AtomicU64>,
    resampler: Arc<Mutex<StreamingResampler>>,
) -> Result<cpal::Stream, String> {
    let writer_clone = Arc::clone(&writer);
    let event_tx_clone = event_tx.clone();
    let errors_tx = event_tx.clone();
    let samples_written_clone = Arc::clone(&samples_written);
    let resampler_clone = Arc::clone(&resampler);

    // Envelope meter (RMS → dBFS → shared envelope) owned by the callback
    let mut meter = LevelMeter::new(sample_rate);
    let mut written = 0_u64;

    // Log first callback
    let first_callback = Arc::new(AtomicBool::new(true));
    let first_callback_clone = Arc::clone(&first_callback);

    eprintln!("[Audio] Building i16 input stream ({} channels)...", channels);

    let stream = device.build_input_stream(
        config,
        move |data: &[i16], info| {
            if first_callback_clone.swap(false, Ordering::Relaxed) {
                eprintln!("[Audio] FIRST CALLBACK: {} raw samples, {} channels → mono downmix + resample",
                    data.len(), channels);
            }

            if is_paused.load(Ordering::Relaxed) {
                return;
            }

            let position = clock.lock().unwrap().position(info);
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

                    if let Err(error) = write_timed_chunk(w, &resampled, position, &mut written) {
                        is_paused.store(true, Ordering::Relaxed);
                        let _ = event_tx_clone.send(RecordingEvent::Error(format!("Audio opslaan mislukt: {error}")));
                        return;
                    }
                    samples_written_clone.store(written, Ordering::Relaxed);
                } else {
                    eprintln!("[Audio] ERROR: writer is None in callback!");
                }
            } else {
                eprintln!("[Audio] ERROR: Failed to lock writer mutex in callback!");
            }
        },
        move |err| { let _ = errors_tx.send(RecordingEvent::Error(format!("Microfoonverbinding onderbroken: {err}"))); },
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
    clock: Arc<Mutex<CaptureClock>>,
    event_tx: mpsc::UnboundedSender<RecordingEvent>,
    samples_written: Arc<AtomicU64>,
    resampler: Arc<Mutex<StreamingResampler>>,
) -> Result<cpal::Stream, String> {
    let writer_clone = Arc::clone(&writer);
    let event_tx_clone = event_tx.clone();
    let errors_tx = event_tx.clone();
    let samples_written_clone = Arc::clone(&samples_written);
    let resampler_clone = Arc::clone(&resampler);

    // Envelope meter (RMS → dBFS → shared envelope) owned by the callback
    let mut meter = LevelMeter::new(sample_rate);
    let mut written = 0_u64;

    // Log first callback
    let first_callback = Arc::new(AtomicBool::new(true));
    let first_callback_clone = Arc::clone(&first_callback);

    eprintln!("[Audio] Building f32 input stream ({} channels)...", channels);

    let stream = device.build_input_stream(
        config,
        move |data: &[f32], info| {
            if first_callback_clone.swap(false, Ordering::Relaxed) {
                eprintln!("[Audio] FIRST CALLBACK (f32): {} raw samples, {} channels → mono downmix + resample",
                    data.len(), channels);
            }

            if is_paused.load(Ordering::Relaxed) {
                return;
            }

            let position = clock.lock().unwrap().position(info);
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

                    if let Err(error) = write_timed_chunk(w, &resampled, position, &mut written) {
                        is_paused.store(true, Ordering::Relaxed);
                        let _ = event_tx_clone.send(RecordingEvent::Error(format!("Audio opslaan mislukt: {error}")));
                        return;
                    }
                    samples_written_clone.store(written, Ordering::Relaxed);
                } else {
                    eprintln!("[Audio] ERROR: writer is None in f32 callback!");
                }
            } else {
                eprintln!("[Audio] ERROR: Failed to lock writer mutex in f32 callback!");
            }
        },
        move |err| { let _ = errors_tx.send(RecordingEvent::Error(format!("Microfoonverbinding onderbroken: {err}"))); },
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
    clock: Arc<Mutex<CaptureClock>>,
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
            let mut written = 0_u64;
            let levels_tx = event_tx.clone();
            let errors_tx = event_tx.clone();

            // Log first callback once
            let first_callback = Arc::new(AtomicBool::new(true));
            let first_callback_clone = Arc::clone(&first_callback);

            let stream = output_device.build_input_stream(
                &config,
                move |data: &[i16], info| {
                    if first_callback_clone.swap(false, Ordering::Relaxed) {
                        eprintln!("[Audio] Loopback FIRST CALLBACK: {} raw samples, {} channels → mono downmix + resample",
                            data.len(), loopback_channels);
                    }

                    if is_paused.load(Ordering::Relaxed) {
                        return;
                    }
                    let position = clock.lock().unwrap().position(info);
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

                            if let Err(error) = write_timed_chunk(w, &resampled, position, &mut written) {
                                is_paused.store(true, Ordering::Relaxed);
                                let _ = levels_tx.send(RecordingEvent::Error(format!("Systeemaudio opslaan mislukt: {error}")));
                            }
                        }
                    }
                },
                move |err| { let _ = errors_tx.send(RecordingEvent::Error(format!("Systeemgeluidverbinding onderbroken: {err}"))); },
                None,
            ).map_err(|e| format!("Loopback i16 stream fout: {}", e))?;
            stream.play().map_err(|e| format!("Kan loopback stream niet starten: {}", e))?;
            Ok(stream)
        }
        cpal::SampleFormat::F32 => {
            let writer_clone = Arc::clone(&writer);
            let resampler_clone = Arc::clone(&loopback_resampler);
            let mut meter = LevelMeter::new(loopback_rate);
            let mut written = 0_u64;
            let levels_tx = event_tx.clone();
            let errors_tx = event_tx.clone();

            // Log first callback once
            let first_callback = Arc::new(AtomicBool::new(true));
            let first_callback_clone = Arc::clone(&first_callback);

            let stream = output_device.build_input_stream(
                &config,
                move |data: &[f32], info| {
                    if first_callback_clone.swap(false, Ordering::Relaxed) {
                        eprintln!("[Audio] Loopback FIRST CALLBACK (f32): {} raw samples, {} channels → mono downmix + resample",
                            data.len(), loopback_channels);
                    }

                    if is_paused.load(Ordering::Relaxed) {
                        return;
                    }
                    let position = clock.lock().unwrap().position(info);
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

                            if let Err(error) = write_timed_chunk(w, &resampled, position, &mut written) {
                                is_paused.store(true, Ordering::Relaxed);
                                let _ = levels_tx.send(RecordingEvent::Error(format!("Systeemaudio opslaan mislukt: {error}")));
                            }
                        }
                    }
                },
                move |err| { let _ = errors_tx.send(RecordingEvent::Error(format!("Systeemgeluidverbinding onderbroken: {err}"))); },
                None,
            ).map_err(|e| format!("Loopback f32 stream fout: {}", e))?;
            stream.play().map_err(|e| format!("Kan loopback stream niet starten: {}", e))?;
            Ok(stream)
        }
        _ => Err("Niet-ondersteunde loopback sample format".to_string()),
    }
}
