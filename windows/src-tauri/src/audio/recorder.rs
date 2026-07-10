use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use cpal::Sample;
use hound::{SampleFormat as HoundSampleFormat, WavSpec, WavWriter};
use std::sync::{Arc, Mutex};
use std::sync::atomic::{AtomicBool, AtomicUsize, AtomicU64, Ordering};
use tokio::sync::mpsc;
use super::types::{AudioDevice, RecordingCommand, RecordingEvent, RecordingMode};

const TARGET_SAMPLE_RATE: u32 = 16000;
const CHANNELS: u16 = 1;
const BITS_PER_SAMPLE: u16 = 16;

/// Streaming resampler that downsamples audio in chunks across callbacks.
/// Uses linear interpolation — sufficient quality for 48→16 kHz speech.
struct StreamingResampler {
    ratio: f64,           // from_rate / to_rate (e.g. 3.0 for 48→16)
    fractional_pos: f64,  // carried over between callbacks
}

impl StreamingResampler {
    fn new(from_rate: u32, to_rate: u32) -> Self {
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
    fn process_i16(&mut self, input: &[i16]) -> Vec<i16> {
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

/// Emit audio level events ~60 times per second
/// Will be calculated dynamically based on actual sample rate
fn level_emit_interval(sample_rate: u32) -> usize {
    (sample_rate / 60) as usize
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
) -> Result<mpsc::Sender<RecordingCommand>, String> {
    let (cmd_tx, mut cmd_rx) = mpsc::channel::<RecordingCommand>(16);
    let output_path_clone = output_path.clone();

    // Capture a handle to the current Tokio runtime so the OS thread can
    // block_on async channel receives.
    let rt_handle = tokio::runtime::Handle::current();

    // cpal streams are !Send on some platforms, so we run everything on a
    // dedicated OS thread rather than a tokio task.
    std::thread::spawn(move || {
        let result = recording_thread_body(
            device_id,
            mode,
            output_path_clone,
            &mut cmd_rx,
            &event_tx,
            &rt_handle,
        );
        if let Err(e) = result {
            let _ = event_tx.send(RecordingEvent::Error(e));
        }
    });

    Ok(cmd_tx)
}

fn recording_thread_body(
    device_id: Option<String>,
    mode: RecordingMode,
    output_path: String,
    cmd_rx: &mut mpsc::Receiver<RecordingCommand>,
    event_tx: &mpsc::UnboundedSender<RecordingEvent>,
    rt_handle: &tokio::runtime::Handle,
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
                Arc::clone(&loopback_writer), Arc::clone(&is_paused),
                event_tx.clone(),
            ) {
                Ok(stream) => {
                    eprintln!("[Audio] Loopback stream gestart voor systeemaudio opname");
                    has_loopback = true;
                    Some(Box::new(stream))
                },
                Err(e) => {
                    eprintln!("[Audio] Loopback niet beschikbaar, alleen microfoon: {}", e);
                    // Clean up in case a file was partially created
                    *loopback_writer.lock().unwrap() = None;
                    let _ = std::fs::remove_file(&loopback_path);
                    has_loopback = false;
                    None
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

    let duration = start.elapsed().as_secs_f64();

    // Log samples written before finalize
    let total_samples = samples_written.load(Ordering::Relaxed);
    eprintln!("[Audio] Stopping recording: {} mono samples written ({:.2}s)", total_samples, duration);

    // Drop streams before finalizing writers
    drop(input_stream);
    drop(_loopback_stream);

    // Finalize mic WAV
    if let Ok(mut guard) = mic_writer.lock() {
        if let Some(w) = guard.take() {
            eprintln!("[Audio] Finalizing mic WAV file...");
            if let Err(e) = w.finalize() {
                eprintln!("[Audio] ERROR finalizing mic WAV: {}", e);
            } else {
                eprintln!("[Audio] Mic WAV file finalized successfully");
            }
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
                if let Err(e) = w.finalize() {
                    eprintln!("[Audio] ERROR finalizing loopback WAV: {}", e);
                } else {
                    eprintln!("[Audio] Loopback WAV file finalized successfully");
                }
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
                eprintln!("[Audio] WARNING: Mixing failed ({}), keeping mic-only audio", e);
                let _ = std::fs::remove_file(&loopback_path);
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

    // Write mixed output using mic spec, overwriting the mic file
    let mut writer = WavWriter::create(mic_path, mic_spec)
        .map_err(|e| format!("Kan mixed WAV niet schrijven: {}", e))?;
    for sample in &mixed {
        writer.write_sample(*sample)
            .map_err(|e| format!("Fout bij schrijven mixed sample: {}", e))?;
    }
    writer.finalize()
        .map_err(|e| format!("Fout bij finaliseren mixed WAV: {}", e))?;

    eprintln!("[Audio] Mixed output: {} samples", mixed.len());
    Ok(())
}

/// Build an input stream for devices that output i16 samples (most Windows devices).
/// Performs stereo-to-mono downmix when channels > 1, then resamples to TARGET_SAMPLE_RATE.
/// Spawns a worker thread that owns the FFT analyzer. The audio callback forwards
/// sample batches via a bounded channel (`try_send` — a full channel drops the batch
/// rather than blocking the callback). The worker emits AudioSpectrum at ~60 Hz and
/// exits when the sender is dropped (stream stop → `recv()` returns Err).
fn spawn_spectrum_worker(
    sample_rate: f32,
    event_tx: mpsc::UnboundedSender<RecordingEvent>,
) -> std::sync::mpsc::SyncSender<Vec<f32>> {
    let (tx, rx) = std::sync::mpsc::sync_channel::<Vec<f32>>(8);
    std::thread::spawn(move || {
        let mut analyzer = crate::audio::spectrum::SpectrumAnalyzer::new(sample_rate);
        let emit_every = ((sample_rate / 60.0) as usize).max(1);
        let mut since_emit: usize = 0;
        while let Ok(batch) = rx.recv() {
            for s in batch {
                analyzer.push(s);
                since_emit += 1;
                if since_emit >= emit_every {
                    since_emit = 0;
                    let (bands, centroid) = analyzer.latest();
                    let _ = event_tx.send(RecordingEvent::AudioSpectrum { bands, centroid });
                }
            }
        }
    });
    tx
}

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

    // Shared state for audio level tracking across callbacks
    let level_counter = Arc::new(AtomicUsize::new(0));
    let level_sum_sq = Arc::new(Mutex::new(0.0f32));
    let level_counter_clone = Arc::clone(&level_counter);
    let level_sum_sq_clone = Arc::clone(&level_sum_sq);

    // FFT runs off-callback on a worker thread; the callback only forwards batches.
    let spectrum_tx = spawn_spectrum_worker(sample_rate as f32, event_tx.clone());

    // Log first callback
    let first_callback = Arc::new(AtomicBool::new(true));
    let first_callback_clone = Arc::clone(&first_callback);

    eprintln!("[Audio] Building i16 input stream ({} channels)...", channels);

    // Calculate emit interval based on actual device sample rate (pre-resample)
    let emit_interval = level_emit_interval(sample_rate);

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
                    let mut spectrum_batch: Vec<f32> = Vec::with_capacity(frame_count);
                    for frame_idx in 0..frame_count {
                        let base = frame_idx * ch;
                        let mut sum: i32 = 0;
                        for c in 0..ch {
                            sum += data[base + c] as i32;
                        }
                        let mono_sample = (sum / channels as i32) as i16;
                        mono_chunk.push(mono_sample);

                        // Calculate audio level on pre-resample samples
                        let normalized = mono_sample.to_float_sample();
                        spectrum_batch.push(normalized);
                        if let Ok(mut sum_sq) = level_sum_sq_clone.lock() {
                            *sum_sq += normalized * normalized;
                        }
                        let level_count = level_counter_clone.fetch_add(1, Ordering::Relaxed) + 1;

                        if level_count >= emit_interval {
                            let rms = if let Ok(sum_sq) = level_sum_sq_clone.lock() {
                                (*sum_sq / level_count as f32).sqrt()
                            } else {
                                0.0
                            };
                            let _ = event_tx_clone.send(RecordingEvent::AudioLevel(rms));
                            level_counter_clone.store(0, Ordering::Relaxed);
                            if let Ok(mut sum_sq) = level_sum_sq_clone.lock() {
                                *sum_sq = 0.0;
                            }
                        }
                    }
                    // Hand the batch to the FFT worker; drop it if the worker is behind.
                    let _ = spectrum_tx.try_send(spectrum_batch);

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

    // Shared state for audio level tracking across callbacks
    let level_counter = Arc::new(AtomicUsize::new(0));
    let level_sum_sq = Arc::new(Mutex::new(0.0f32));
    let level_counter_clone = Arc::clone(&level_counter);
    let level_sum_sq_clone = Arc::clone(&level_sum_sq);

    // FFT runs off-callback on a worker thread; the callback only forwards batches.
    let spectrum_tx = spawn_spectrum_worker(sample_rate as f32, event_tx.clone());

    // Log first callback
    let first_callback = Arc::new(AtomicBool::new(true));
    let first_callback_clone = Arc::clone(&first_callback);

    eprintln!("[Audio] Building f32 input stream ({} channels)...", channels);

    // Calculate emit interval based on actual device sample rate (pre-resample)
    let emit_interval = level_emit_interval(sample_rate);

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
                    let mut spectrum_batch: Vec<f32> = Vec::with_capacity(frame_count);
                    for frame_idx in 0..frame_count {
                        let base = frame_idx * ch;
                        let mut sum: f32 = 0.0;
                        for c in 0..ch {
                            sum += data[base + c];
                        }
                        let mono_sample = sum / channels as f32;
                        let s16 = (mono_sample.clamp(-1.0, 1.0) * i16::MAX as f32) as i16;
                        mono_chunk.push(s16);

                        // Calculate audio level on pre-resample samples
                        spectrum_batch.push(mono_sample);
                        if let Ok(mut sum_sq) = level_sum_sq_clone.lock() {
                            *sum_sq += mono_sample * mono_sample;
                        }
                        let level_count = level_counter_clone.fetch_add(1, Ordering::Relaxed) + 1;

                        if level_count >= emit_interval {
                            let rms = if let Ok(sum_sq) = level_sum_sq_clone.lock() {
                                (*sum_sq / level_count as f32).sqrt()
                            } else {
                                0.0
                            };
                            let _ = event_tx_clone.send(RecordingEvent::AudioLevel(rms));
                            level_counter_clone.store(0, Ordering::Relaxed);
                            if let Ok(mut sum_sq) = level_sum_sq_clone.lock() {
                                *sum_sq = 0.0;
                            }
                        }
                    }
                    // Hand the batch to the FFT worker; drop it if the worker is behind.
                    let _ = spectrum_tx.try_send(spectrum_batch);

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
            let event_tx_clone = event_tx.clone();
            let resampler_clone = Arc::clone(&loopback_resampler);

            // Audio level tracking for loopback stream
            let level_counter = Arc::new(AtomicUsize::new(0));
            let level_sum_sq = Arc::new(Mutex::new(0.0f32));
            let level_counter_clone = Arc::clone(&level_counter);
            let level_sum_sq_clone = Arc::clone(&level_sum_sq);

            // Log first callback once
            let first_callback = Arc::new(AtomicBool::new(true));
            let first_callback_clone = Arc::clone(&first_callback);

            // Calculate emit interval based on actual device sample rate
            let emit_interval = level_emit_interval(loopback_rate);

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

                            // Step 1: Downmix to mono
                            let mut mono_chunk: Vec<i16> = Vec::with_capacity(frame_count);
                            for frame_idx in 0..frame_count {
                                let base = frame_idx * ch;
                                let mut sum: i32 = 0;
                                for c in 0..ch {
                                    sum += data[base + c] as i32;
                                }
                                let mono_sample = (sum / loopback_channels as i32) as i16;
                                mono_chunk.push(mono_sample);

                                // Calculate audio level on pre-resample samples
                                let normalized = mono_sample.to_float_sample();
                                if let Ok(mut sum_sq) = level_sum_sq_clone.lock() {
                                    *sum_sq += normalized * normalized;
                                }
                                let count = level_counter_clone.fetch_add(1, Ordering::Relaxed) + 1;

                                if count >= emit_interval {
                                    let rms = if let Ok(sum_sq) = level_sum_sq_clone.lock() {
                                        (*sum_sq / count as f32).sqrt()
                                    } else {
                                        0.0
                                    };
                                    let _ = event_tx_clone.send(RecordingEvent::AudioLevel(rms));
                                    level_counter_clone.store(0, Ordering::Relaxed);
                                    if let Ok(mut sum_sq) = level_sum_sq_clone.lock() {
                                        *sum_sq = 0.0;
                                    }
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
            let event_tx_clone = event_tx.clone();
            let resampler_clone = Arc::clone(&loopback_resampler);

            // Audio level tracking for loopback stream
            let level_counter = Arc::new(AtomicUsize::new(0));
            let level_sum_sq = Arc::new(Mutex::new(0.0f32));
            let level_counter_clone = Arc::clone(&level_counter);
            let level_sum_sq_clone = Arc::clone(&level_sum_sq);

            // Log first callback once
            let first_callback = Arc::new(AtomicBool::new(true));
            let first_callback_clone = Arc::clone(&first_callback);

            // Calculate emit interval based on actual device sample rate
            let emit_interval = level_emit_interval(loopback_rate);

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
                                let s16 = (mono_sample.clamp(-1.0, 1.0) * i16::MAX as f32) as i16;
                                mono_chunk.push(s16);

                                // Calculate audio level on pre-resample samples
                                if let Ok(mut sum_sq) = level_sum_sq_clone.lock() {
                                    *sum_sq += mono_sample * mono_sample;
                                }
                                let count = level_counter_clone.fetch_add(1, Ordering::Relaxed) + 1;

                                if count >= emit_interval {
                                    let rms = if let Ok(sum_sq) = level_sum_sq_clone.lock() {
                                        (*sum_sq / count as f32).sqrt()
                                    } else {
                                        0.0
                                    };
                                    let _ = event_tx_clone.send(RecordingEvent::AudioLevel(rms));
                                    level_counter_clone.store(0, Ordering::Relaxed);
                                    if let Ok(mut sum_sq) = level_sum_sq_clone.lock() {
                                        *sum_sq = 0.0;
                                    }
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
