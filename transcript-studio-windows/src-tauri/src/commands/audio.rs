use std::sync::{Arc, Mutex};
use tokio::sync::mpsc;
use tauri::{AppHandle, Emitter};
use crate::audio::{
    recorder,
    types::{AudioDevice, RecordingCommand, RecordingEvent, RecordingMode, RecordingResult},
};

/// Shared recording state stored in Tauri's managed state.
/// Uses channels to avoid storing non-Send cpal Streams in state.
pub struct RecordingState {
    pub cmd_tx: Option<mpsc::Sender<RecordingCommand>>,
    pub is_recording: bool,
    pub is_paused: bool,
    pub file_path: Option<String>,
}

impl Default for RecordingState {
    fn default() -> Self {
        Self {
            cmd_tx: None,
            is_recording: false,
            is_paused: false,
            file_path: None,
        }
    }
}

pub type SharedRecordingState = Arc<Mutex<RecordingState>>;

#[tauri::command]
pub async fn get_audio_devices() -> Result<Vec<AudioDevice>, String> {
    Ok(recorder::get_devices())
}

#[tauri::command]
pub async fn start_recording(
    app: AppHandle,
    state: tauri::State<'_, SharedRecordingState>,
    device_id: Option<String>,
    mode: String,
    output_dir: String,
) -> Result<String, String> {
    let mut guard = state.lock().map_err(|e| e.to_string())?;

    if guard.is_recording {
        return Err("Er loopt al een opname".to_string());
    }

    let recording_mode = match mode.as_str() {
        "combined" => RecordingMode::Combined,
        _ => RecordingMode::Microphone,
    };

    // Ensure output directory exists
    std::fs::create_dir_all(&output_dir)
        .map_err(|e| format!("Kan map niet aanmaken: {}", e))?;

    let timestamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis())
        .unwrap_or(0);
    let filename = format!("recording_{}.wav", timestamp);
    let file_path = format!("{}/{}", output_dir.trim_end_matches('/'), filename);

    // Set up event forwarding from recording thread → Tauri events
    let (event_tx, mut event_rx) = mpsc::unbounded_channel::<RecordingEvent>();
    let app_clone = app.clone();

    tokio::spawn(async move {
        while let Some(event) = event_rx.recv().await {
            match event {
                RecordingEvent::AudioLevel(level) => {
                    let _ = app_clone.emit("audio-level", level);
                }
                RecordingEvent::Stopped { file_path, duration_seconds } => {
                    let _ = app_clone.emit("recording-stopped", serde_json::json!({
                        "file_path": file_path,
                        "duration_seconds": duration_seconds
                    }));
                }
                RecordingEvent::Error(e) => {
                    let _ = app_clone.emit("recording-error", e);
                }
            }
        }
    });

    let cmd_tx = recorder::start_recording_thread(
        device_id,
        recording_mode,
        file_path.clone(),
        event_tx,
    )?;

    guard.cmd_tx = Some(cmd_tx);
    guard.is_recording = true;
    guard.is_paused = false;
    guard.file_path = Some(file_path.clone());

    Ok(file_path)
}

#[tauri::command]
pub async fn stop_recording(
    state: tauri::State<'_, SharedRecordingState>,
) -> Result<RecordingResult, String> {
    let (cmd_tx, file_path) = {
        let mut guard = state.lock().map_err(|e| e.to_string())?;
        if !guard.is_recording {
            return Err("Er is geen actieve opname".to_string());
        }
        let cmd_tx = guard.cmd_tx.take();
        let file_path = guard.file_path.clone().unwrap_or_default();
        guard.is_recording = false;
        guard.is_paused = false;
        (cmd_tx, file_path)
    };

    if let Some(tx) = cmd_tx {
        let _ = tx.send(RecordingCommand::Stop).await;
        // Small delay to allow thread to finalize WAV
        tokio::time::sleep(tokio::time::Duration::from_millis(300)).await;
    }

    // Calculate duration from WAV file
    let duration_seconds = get_wav_duration(&file_path).unwrap_or(0.0);

    Ok(RecordingResult { file_path, duration_seconds })
}

#[tauri::command]
pub async fn pause_recording(
    state: tauri::State<'_, SharedRecordingState>,
) -> Result<(), String> {
    let guard = state.lock().map_err(|e| e.to_string())?;

    if !guard.is_recording {
        return Err("Geen actieve opname".to_string());
    }

    if guard.is_paused {
        // Already paused — no-op is fine
        return Ok(());
    }

    if let Some(ref tx) = guard.cmd_tx {
        tx.try_send(RecordingCommand::Pause)
            .map_err(|e| format!("Pauze mislukt: {}", e))?;
    } else {
        return Err("Opnamekanaal is gesloten".to_string());
    }

    Ok(())
}

#[tauri::command]
pub async fn resume_recording(
    state: tauri::State<'_, SharedRecordingState>,
) -> Result<(), String> {
    let guard = state.lock().map_err(|e| e.to_string())?;

    if !guard.is_recording {
        return Err("Geen actieve opname".to_string());
    }

    if !guard.is_paused {
        // Already recording — no-op is fine
        return Ok(());
    }

    if let Some(ref tx) = guard.cmd_tx {
        tx.try_send(RecordingCommand::Resume)
            .map_err(|e| format!("Hervatten mislukt: {}", e))?;
    } else {
        return Err("Opnamekanaal is gesloten".to_string());
    }

    Ok(())
}

fn get_wav_duration(file_path: &str) -> Option<f64> {
    let reader = hound::WavReader::open(file_path).ok()?;
    let spec = reader.spec();
    let num_samples = reader.len();
    Some(num_samples as f64 / spec.sample_rate as f64)
}
