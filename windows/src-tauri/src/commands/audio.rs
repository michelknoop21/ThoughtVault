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
    pub completion: Option<tokio::sync::oneshot::Receiver<Result<RecordingResult, String>>>,
}

impl Default for RecordingState {
    fn default() -> Self {
        Self {
            cmd_tx: None,
            is_recording: false,
            is_paused: false,
            file_path: None,
            completion: None,
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
    let (file_path, ready) = {
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
        let (done_tx, done_rx) = tokio::sync::oneshot::channel();

        let shared_state = Arc::clone(state.inner());
        let session_path = file_path.clone();
        tokio::spawn(async move {
            let now = std::time::Instant::now();
            let mut mic = (0.0, now);
            let mut system = (0.0, now);
            let mut ticker = tokio::time::interval(std::time::Duration::from_millis(33));
            loop {
                tokio::select! {
                    _ = ticker.tick() => {
                        let level = combined_level(mic, system, std::time::Instant::now());
                        let _ = app_clone.emit("audio-level", level);
                    }
                    event = event_rx.recv() => match event {
                        Some(RecordingEvent::AudioLevel(level)) => mic = (level, std::time::Instant::now()),
                        Some(RecordingEvent::SystemAudioLevel(level)) => system = (level, std::time::Instant::now()),
                        Some(RecordingEvent::Stopped { file_path, duration_seconds }) => {
                            let _ = done_tx.send(Ok(RecordingResult { file_path: file_path.clone(), duration_seconds }));
                            let _ = app_clone.emit("audio-level", 0.0_f32);
                            let _ = app_clone.emit("recording-stopped", serde_json::json!({ "file_path": file_path, "duration_seconds": duration_seconds }));
                            break;
                        }
                        Some(RecordingEvent::Error(error)) => {
                            let _ = done_tx.send(Err(error.clone()));
                            if let Ok(mut state) = shared_state.lock() {
                                if state.file_path.as_ref() == Some(&session_path) { *state = RecordingState::default(); }
                            }
                            let _ = app_clone.emit("audio-level", 0.0_f32);
                            let _ = app_clone.emit("recording-error", error);
                            break;
                        }
                        None => break,
                    }
                }
            }
        });

        let (cmd_tx, ready) = recorder::start_recording_thread(
            device_id,
            recording_mode,
            file_path.clone(),
            event_tx,
        )?;

        guard.cmd_tx = Some(cmd_tx);
        guard.is_recording = true;
        guard.is_paused = false;
        guard.file_path = Some(file_path.clone());
        guard.completion = Some(done_rx);

        (file_path, ready)
    };
    ready.await.map_err(|_| "Opname-thread is gestopt tijdens het starten".to_string())??;
    Ok(file_path)
}

#[tauri::command]
pub async fn stop_recording(
    state: tauri::State<'_, SharedRecordingState>,
) -> Result<RecordingResult, String> {
    let (cmd_tx, completion, file_path) = {
        let mut guard = state.lock().map_err(|e| e.to_string())?;
        if !guard.is_recording { return Err("Er is geen actieve opname".to_string()); }
        if guard.completion.is_none() { return Err("De opname wordt al opgeslagen".to_string()); }
        guard.is_paused = false;
        (guard.cmd_tx.take(), guard.completion.take(), guard.file_path.clone())
    };
    if let Some(tx) = cmd_tx {
        tx.send(RecordingCommand::Stop).await.map_err(|_| "Opname-thread is gestopt".to_string())?;
    }
    let completion = completion.ok_or("Opname-resultaat niet beschikbaar")?;
    let result = tokio::time::timeout(std::time::Duration::from_secs(60), completion).await
        .map_err(|_| "Opslaan van de opname duurt te lang. Controleer Opgeslagen opnames.".to_string())?
        .map_err(|_| "Opname-thread is gestopt zonder resultaat".to_string())?;
    let mut guard = state.lock().map_err(|e| e.to_string())?;
    if guard.file_path == file_path { *guard = RecordingState::default(); }
    result
}

#[tauri::command]
pub async fn pause_recording(
    state: tauri::State<'_, SharedRecordingState>,
) -> Result<(), String> {
    let mut guard = state.lock().map_err(|e| e.to_string())?;

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

    // Update shared state to reflect paused status
    guard.is_paused = true;

    Ok(())
}

#[tauri::command]
pub async fn resume_recording(
    state: tauri::State<'_, SharedRecordingState>,
) -> Result<(), String> {
    let mut guard = state.lock().map_err(|e| e.to_string())?;

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

    // Update shared state to reflect recording status
    guard.is_paused = false;

    Ok(())
}

#[cfg(test)]
mod level_tests {
    use super::*;
    #[test]
    fn system_audio_drives_meter_with_a_silent_microphone_and_expires() {
        let now = std::time::Instant::now();
        assert_eq!(combined_level((0.0, now), (0.8, now), now), 0.8);
        assert_eq!(combined_level((0.9, now), (0.2, now), now), 0.9);
        assert_eq!(combined_level((0.0, now), (0.8, now), now + std::time::Duration::from_millis(200)), 0.0);
    }
}

// Publish one combined envelope at 30 Hz; alternating source events must not
// make a silent microphone suppress system audio. Expire stalled/paused streams.
fn combined_level(mic: (f32, std::time::Instant), system: (f32, std::time::Instant), now: std::time::Instant) -> f32 {
    [mic, system].into_iter().map(|(level, updated)| {
        if now.duration_since(updated).as_millis() <= 150 && level.is_finite() { level.clamp(0.0, 1.0) } else { 0.0 }
    }).fold(0.0, f32::max)
}
