use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use hound::{SampleFormat, WavSpec, WavWriter};
use std::sync::{Arc, Mutex};
use std::sync::atomic::{AtomicBool, Ordering};
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

    let config = cpal::StreamConfig {
        channels: CHANNELS,
        sample_rate: cpal::SampleRate(SAMPLE_RATE),
        buffer_size: cpal::BufferSize::Default,
    };

    let wav_spec = WavSpec {
        channels: CHANNELS,
        sample_rate: SAMPLE_RATE,
        bits_per_sample: BITS_PER_SAMPLE,
        sample_format: SampleFormat::Int,
    };

    let writer = WavWriter::create(&output_path, wav_spec)
        .map_err(|e| format!("Kan opnamebestand niet aanmaken: {}", e))?;
    let writer = Arc::new(Mutex::new(Some(writer)));
    let writer_clone = Arc::clone(&writer);

    let is_paused = Arc::new(AtomicBool::new(false));
    let is_paused_clone = Arc::clone(&is_paused);

    let event_tx_clone = event_tx.clone();
    let mut level_sample_counter = 0usize;
    let mut level_sum_sq = 0.0f32;

    let input_stream = input_device.build_input_stream(
        &config,
        move |data: &[f32], _| {
            if is_paused_clone.load(Ordering::Relaxed) {
                return;
            }

            // Write samples
            if let Ok(mut guard) = writer_clone.lock() {
                if let Some(ref mut w) = *guard {
                    for &sample in data {
                        let s16 = (sample.clamp(-1.0, 1.0) * i16::MAX as f32) as i16;
                        let _ = w.write_sample(s16);
                        level_sum_sq += sample * sample;
                        level_sample_counter += 1;
                        if level_sample_counter >= LEVEL_EMIT_INTERVAL_SAMPLES {
                            let rms = (level_sum_sq / level_sample_counter as f32).sqrt();
                            let _ = event_tx_clone.send(RecordingEvent::AudioLevel(rms));
                            level_sum_sq = 0.0;
                            level_sample_counter = 0;
                        }
                    }
                }
            }
        },
        |err| eprintln!("[Audio] Stream error: {}", err),
        None,
    ).map_err(|e| format!("Kan audio stream niet openen: {}", e))?;

    // Optional loopback stream for combined mode (Windows WASAPI loopback)
    let _loopback_stream: Option<Box<dyn StreamTrait>> = if mode == RecordingMode::Combined {
        // Try to get a WASAPI loopback device (render → loopback capture)
        // On non-Windows or if unavailable, silently skip
        #[cfg(target_os = "windows")]
        {
            match try_build_loopback_stream(&host, Arc::clone(&writer), Arc::clone(&is_paused)) {
                Ok(stream) => Some(Box::new(stream)),
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

    // Finalize WAV
    drop(input_stream);
    if let Ok(mut guard) = writer.lock() {
        if let Some(w) = guard.take() {
            let _ = w.finalize();
        }
    }

    let _ = event_tx.send(RecordingEvent::Stopped {
        file_path: output_path,
        duration_seconds: duration,
    });

    Ok(())
}

/// Build a WASAPI loopback capture stream on Windows.
/// The loopback mixes into the same WAV writer.
#[cfg(target_os = "windows")]
fn try_build_loopback_stream(
    host: &cpal::Host,
    writer: Arc<Mutex<Option<WavWriter<std::io::BufWriter<std::fs::File>>>>>,
    is_paused: Arc<AtomicBool>,
) -> Result<impl StreamTrait, String> {
    use cpal::traits::HostTrait;

    // On WASAPI: enumerate output devices — they support loopback capture
    let output_device = host.default_output_device()
        .ok_or("Geen standaard uitvoerapparaat voor loopback")?;

    let config = cpal::StreamConfig {
        channels: CHANNELS,
        sample_rate: cpal::SampleRate(SAMPLE_RATE),
        buffer_size: cpal::BufferSize::Default,
    };

    let stream = output_device.build_input_stream(
        &config,
        move |data: &[f32], _| {
            if is_paused.load(Ordering::Relaxed) {
                return;
            }
            if let Ok(mut guard) = writer.lock() {
                if let Some(ref mut w) = *guard {
                    for &sample in data {
                        let s16 = (sample.clamp(-1.0, 1.0) * i16::MAX as f32) as i16;
                        let _ = w.write_sample(s16);
                    }
                }
            }
        },
        |err| eprintln!("[Audio] Loopback stream error: {}", err),
        None,
    ).map_err(|e| format!("Loopback stream fout: {}", e))?;

    stream.play().map_err(|e| format!("Kan loopback stream niet starten: {}", e))?;
    Ok(stream)
}
