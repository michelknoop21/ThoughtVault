use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use cpal::Sample;
use hound::{SampleFormat as HoundSampleFormat, WavSpec, WavWriter};
use std::sync::{Arc, Mutex};
use std::sync::atomic::{AtomicBool, AtomicUsize, AtomicU64, Ordering};
use tokio::sync::mpsc;
use super::types::{AudioDevice, RecordingCommand, RecordingEvent, RecordingMode};

const SAMPLE_RATE: u32 = 16000;
const CHANNELS: u16 = 1;
const BITS_PER_SAMPLE: u16 = 16;
/// Emit audio level events ~60 times per second
const LEVEL_EMIT_INTERVAL_SAMPLES: usize = SAMPLE_RATE as usize / 60;

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
    let supported = input_device
        .supported_input_configs()
        .map_err(|e| format!("Kan audio configs niet lezen: {}", e))?
        .find(|c| c.channels() >= CHANNELS && c.min_sample_rate() <= cpal::SampleRate(SAMPLE_RATE)
            && c.max_sample_rate() >= cpal::SampleRate(SAMPLE_RATE))
        .ok_or("Geen geschikte audio configuratie gevonden")?;

    let sample_format = supported.sample_format();
    let config: cpal::StreamConfig = supported.clone().with_sample_rate(cpal::SampleRate(SAMPLE_RATE)).into();

    eprintln!("[Audio] Device sample format: {:?}, config: {:?}", sample_format, config);

    let wav_spec = WavSpec {
        channels: CHANNELS,
        sample_rate: SAMPLE_RATE,
        bits_per_sample: BITS_PER_SAMPLE,
        sample_format: HoundSampleFormat::Int,
    };

    let writer = WavWriter::create(&output_path, wav_spec)
        .map_err(|e| format!("Kan opnamebestand niet aanmaken: {}", e))?;
    let writer = Arc::new(Mutex::new(Some(writer)));
    let writer_clone = Arc::clone(&writer);

    let is_paused = Arc::new(AtomicBool::new(false));
    let is_paused_clone = Arc::clone(&is_paused);

    // Track samples written for debugging
    let samples_written = Arc::new(AtomicU64::new(0));
    let samples_written_clone = Arc::clone(&samples_written);

    let event_tx_clone = event_tx.clone();

    eprintln!("[Audio] WAV file created: {}", output_path);

    // Build the appropriate input stream based on the device's sample format
    let input_stream = match sample_format {
        cpal::SampleFormat::I16 => build_input_stream_i16(
            &input_device, &config, writer_clone, is_paused_clone, event_tx_clone, samples_written_clone,
        )?,
        cpal::SampleFormat::F32 => build_input_stream_f32(
            &input_device, &config, writer_clone, is_paused_clone, event_tx_clone, samples_written_clone,
        )?,
        _ => return Err("Niet-ondersteunde sample format".to_string()),
    };

    // Optional loopback stream for combined mode (Windows WASAPI loopback)
    // IMPORTANT: Keep this alive until recording stops - dropping the stream stops callbacks!
    let loopback_stream_holder: Option<Box<dyn StreamTrait>> = if mode == RecordingMode::Combined {
        #[cfg(target_os = "windows")]
        {
            match try_build_loopback_stream(&host, Arc::clone(&writer), Arc::clone(&is_paused), event_tx.clone()) {
                Ok(stream) => {
                    eprintln!("[Audio] Loopback stream gestart voor systeemaudio opname");
                    Some(Box::new(stream))
                },
                Err(e) => {
                    eprintln!("[Audio] Loopback niet beschikbaar, alleen microfoon: {}", e);
                    None
                }
            }
        }
        #[cfg(not(target_os = "windows"))]
        None
    } else {
        None
    };

    // Prevent "unused" warning - we explicitly keep this alive
    let _ = loopback_stream_holder;

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
    eprintln!("[Audio] Stopping recording: {} samples written ({:.2}s)", total_samples, duration);

    // Finalize WAV
    drop(input_stream);
    if let Ok(mut guard) = writer.lock() {
        if let Some(w) = guard.take() {
            eprintln!("[Audio] Finalizing WAV file...");
            if let Err(e) = w.finalize() {
                eprintln!("[Audio] ERROR finalizing WAV: {}", e);
            } else {
                eprintln!("[Audio] WAV file finalized successfully");
            }
        } else {
            eprintln!("[Audio] ERROR: writer was already None during finalize!");
        }
    } else {
        eprintln!("[Audio] ERROR: Failed to lock writer for finalize!");
    }

    let output_path_clone = output_path.clone();
    let _ = event_tx.send(RecordingEvent::Stopped {
        file_path: output_path_clone,
        duration_seconds: duration,
    });

    eprintln!("[Audio] Recording stopped, file: {}", output_path);

    Ok(())
}

/// Build an input stream for devices that output i16 samples (most Windows devices)
fn build_input_stream_i16(
    device: &cpal::Device,
    config: &cpal::StreamConfig,
    writer: Arc<Mutex<Option<WavWriter<std::io::BufWriter<std::fs::File>>>>>,
    is_paused: Arc<AtomicBool>,
    event_tx: mpsc::UnboundedSender<RecordingEvent>,
    samples_written: Arc<AtomicU64>,
) -> Result<cpal::Stream, String> {
    let writer_clone = Arc::clone(&writer);
    let event_tx_clone = event_tx.clone();
    let samples_written_clone = Arc::clone(&samples_written);

    // Shared state for audio level tracking across callbacks
    let level_counter = Arc::new(AtomicUsize::new(0));
    let level_sum_sq = Arc::new(Mutex::new(0.0f32));
    let level_counter_clone = Arc::clone(&level_counter);
    let level_sum_sq_clone = Arc::clone(&level_sum_sq);

    // Log first callback
    let first_callback = Arc::new(AtomicBool::new(true));
    let first_callback_clone = Arc::clone(&first_callback);

    eprintln!("[Audio] Building i16 input stream...");

    let stream = device.build_input_stream(
        config,
        move |data: &[i16], _| {
            if first_callback_clone.swap(false, Ordering::Relaxed) {
                eprintln!("[Audio] FIRST CALLBACK: {} samples received", data.len());
            }

            if is_paused.load(Ordering::Relaxed) {
                return;
            }

            if let Ok(mut guard) = writer_clone.lock() {
                if let Some(ref mut w) = *guard {
                    for &sample in data {
                        // Write i16 directly to WAV
                        let _ = w.write_sample(sample);

                        // Track samples written
                        let count = samples_written_clone.fetch_add(1, Ordering::Relaxed) + 1;

                        // Log every ~5 seconds (5 * 16000 = 80000 samples)
                        if count % 80000 == 0 {
                            eprintln!("[Audio] Written {} samples (~{} seconds)", count, count / 16000);
                        }

                        // Calculate audio level for visualization
                        // Normalize i16 to f32 in [-1.0, 1.0]
                        let normalized = sample.to_float_sample();
                        if let Ok(mut sum_sq) = level_sum_sq_clone.lock() {
                            *sum_sq += normalized * normalized;
                        }
                        let level_count = level_counter_clone.fetch_add(1, Ordering::Relaxed) + 1;

                        if level_count >= LEVEL_EMIT_INTERVAL_SAMPLES {
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

/// Build an input stream for devices that output f32 samples
fn build_input_stream_f32(
    device: &cpal::Device,
    config: &cpal::StreamConfig,
    writer: Arc<Mutex<Option<WavWriter<std::io::BufWriter<std::fs::File>>>>>,
    is_paused: Arc<AtomicBool>,
    event_tx: mpsc::UnboundedSender<RecordingEvent>,
    samples_written: Arc<AtomicU64>,
) -> Result<cpal::Stream, String> {
    let writer_clone = Arc::clone(&writer);
    let event_tx_clone = event_tx.clone();
    let samples_written_clone = Arc::clone(&samples_written);

    // Shared state for audio level tracking across callbacks
    let level_counter = Arc::new(AtomicUsize::new(0));
    let level_sum_sq = Arc::new(Mutex::new(0.0f32));
    let level_counter_clone = Arc::clone(&level_counter);
    let level_sum_sq_clone = Arc::clone(&level_sum_sq);

    // Log first callback
    let first_callback = Arc::new(AtomicBool::new(true));
    let first_callback_clone = Arc::clone(&first_callback);

    eprintln!("[Audio] Building f32 input stream...");

    let stream = device.build_input_stream(
        config,
        move |data: &[f32], _| {
            if first_callback_clone.swap(false, Ordering::Relaxed) {
                eprintln!("[Audio] FIRST CALLBACK (f32): {} samples received", data.len());
            }

            if is_paused.load(Ordering::Relaxed) {
                return;
            }

            if let Ok(mut guard) = writer_clone.lock() {
                if let Some(ref mut w) = *guard {
                    for &sample in data {
                        // Convert f32 to i16 for WAV output
                        let s16 = (sample.clamp(-1.0, 1.0) * i16::MAX as f32) as i16;
                        let _ = w.write_sample(s16);

                        // Track samples written
                        let count = samples_written_clone.fetch_add(1, Ordering::Relaxed) + 1;

                        // Log every ~5 seconds
                        if count % 80000 == 0 {
                            eprintln!("[Audio] Written {} samples (~{} seconds)", count, count / 16000);
                        }

                        if let Ok(mut sum_sq) = level_sum_sq_clone.lock() {
                            *sum_sq += sample * sample;
                        }
                        let level_count = level_counter_clone.fetch_add(1, Ordering::Relaxed) + 1;

                        if level_count >= LEVEL_EMIT_INTERVAL_SAMPLES {
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
/// The loopback mixes into the same WAV writer.
#[cfg(target_os = "windows")]
fn try_build_loopback_stream(
    host: &cpal::Host,
    writer: Arc<Mutex<Option<WavWriter<std::io::BufWriter<std::fs::File>>>>>,
    is_paused: Arc<AtomicBool>,
    event_tx: mpsc::UnboundedSender<RecordingEvent>,
) -> Result<impl StreamTrait, String> {
    use cpal::traits::HostTrait;

    // On WASAPI: enumerate output devices — they support loopback capture
    let output_device = host.default_output_device()
        .ok_or("Geen standaard uitvoerapparaat voor loopback")?;

    // Probe loopback device for supported format
    let supported = output_device
        .supported_input_configs()
        .map_err(|e| format!("Kan loopback configs niet lezen: {}", e))?
        .find(|c| c.channels() >= CHANNELS && c.min_sample_rate() <= cpal::SampleRate(SAMPLE_RATE)
            && c.max_sample_rate() >= cpal::SampleRate(SAMPLE_RATE))
        .ok_or("Geen geschikte loopback configuratie gevonden")?;

    let sample_format = supported.sample_format();
    let config: cpal::StreamConfig = supported.clone().with_sample_rate(cpal::SampleRate(SAMPLE_RATE)).into();

    // Loopback also needs format-specific handling
    match sample_format {
        cpal::SampleFormat::I16 => {
            let writer_clone = Arc::clone(&writer);
            let event_tx_clone = event_tx.clone();

            // Audio level tracking for loopback stream
            let level_counter = Arc::new(AtomicUsize::new(0));
            let level_sum_sq = Arc::new(Mutex::new(0.0f32));
            let level_counter_clone = Arc::clone(&level_counter);
            let level_sum_sq_clone = Arc::clone(&level_sum_sq);

            let stream = output_device.build_input_stream(
                &config,
                move |data: &[i16], _| {
                    if is_paused.load(Ordering::Relaxed) {
                        return;
                    }
                    if let Ok(mut guard) = writer_clone.lock() {
                        if let Some(ref mut w) = &mut *guard {
                            for &sample in data {
                                let _ = w.write_sample(sample);

                                // Calculate audio level for visualization
                                let normalized = sample.to_float_sample();
                                if let Ok(mut sum_sq) = level_sum_sq_clone.lock() {
                                    *sum_sq += normalized * normalized;
                                }
                                let count = level_counter_clone.fetch_add(1, Ordering::Relaxed) + 1;

                                if count >= LEVEL_EMIT_INTERVAL_SAMPLES {
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

            // Audio level tracking for loopback stream
            let level_counter = Arc::new(AtomicUsize::new(0));
            let level_sum_sq = Arc::new(Mutex::new(0.0f32));
            let level_counter_clone = Arc::clone(&level_counter);
            let level_sum_sq_clone = Arc::clone(&level_sum_sq);

            let stream = output_device.build_input_stream(
                &config,
                move |data: &[f32], _| {
                    if is_paused.load(Ordering::Relaxed) {
                        return;
                    }
                    if let Ok(mut guard) = writer_clone.lock() {
                        if let Some(ref mut w) = &mut *guard {
                            for &sample in data {
                                let s16 = (sample.clamp(-1.0, 1.0) * i16::MAX as f32) as i16;
                                let _ = w.write_sample(s16);

                                // Calculate audio level for visualization
                                if let Ok(mut sum_sq) = level_sum_sq_clone.lock() {
                                    *sum_sq += sample * sample;
                                }
                                let count = level_counter_clone.fetch_add(1, Ordering::Relaxed) + 1;

                                if count >= LEVEL_EMIT_INTERVAL_SAMPLES {
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
