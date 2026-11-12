use std::sync::{Arc, Mutex};
use tokio::sync::mpsc;
use tauri::{AppHandle, Emitter};
use crate::audio::{
    recorder,
    types::{AudioDevice, RecordingCommand, RecordingEvent, RecordingMode, RecordingResult, RecordingDiagnosticCode, RecordingCommandError, TerminalDiagnostic},
};

fn emit_diagnostic(app: &AppHandle, code: RecordingDiagnosticCode) {
    let _ = app.emit("recording-diagnostic", code);
}
fn emit_terminal(app: &AppHandle, terminal: &TerminalDiagnostic, fallback: RecordingDiagnosticCode) {
    terminal.claim(fallback);
    if let Some(code) = terminal.take() { emit_diagnostic(app, code); }
}
fn command_failure(app: &AppHandle, code: RecordingDiagnosticCode, message: impl Into<String>) -> RecordingCommandError {
    emit_diagnostic(app, code);
    RecordingCommandError::native_owned(message)
}

/// Shared recording state stored in Tauri's managed state.
/// Uses channels to avoid storing non-Send cpal Streams in state.
pub struct RecordingState {
    pub terminal: Option<Arc<TerminalDiagnostic>>,
    pub cmd_tx: Option<mpsc::Sender<RecordingCommand>>,
    pub is_recording: bool,
    pub is_paused: bool,
    pub file_path: Option<String>,
    pub completion: Option<tokio::sync::oneshot::Receiver<Result<RecordingResult, String>>>,
}

impl Default for RecordingState {
    fn default() -> Self {
        Self {
            terminal: None,
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
pub fn recording_active(state: tauri::State<'_, SharedRecordingState>) -> bool {
    // Contention or poisoning is uncertainty, so do not permit close/install.
    state.try_lock().map(|guard| guard.is_recording).unwrap_or(true)
}

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
) -> Result<String, RecordingCommandError> {
    let terminal = Arc::new(TerminalDiagnostic::default());
    let (file_path, ready) = {
        let mut guard = state.lock().map_err(|e| command_failure(&app, RecordingDiagnosticCode::StartFailed, e.to_string()))?;

        if guard.is_recording {
            return Err(RecordingCommandError::expected("Er loopt al een opname"));
        }

        let recording_mode = match mode.as_str() {
            "combined" => RecordingMode::Combined,
            _ => RecordingMode::Microphone,
        };

        // Ensure output directory exists
        std::fs::create_dir_all(&output_dir)
            .map_err(|e| command_failure(&app, RecordingDiagnosticCode::StartFailed, format!("Kan map niet aanmaken: {}", e)))?;

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
        let event_terminal = Arc::clone(&terminal);
        tokio::spawn(async move {
            let now = std::time::Instant::now();
            let mut mic = (0.0, now);
            let mut system = (0.0, now);
            let mut mic_bands = ([0.0_f32; 7], now);
            let mut system_bands = ([0.0_f32; 7], now);
            let mut ticker = tokio::time::interval(std::time::Duration::from_millis(33));
            loop {
                tokio::select! {
                    _ = ticker.tick() => {
                        let level = combined_level(mic, system, std::time::Instant::now());
                        let _ = app_clone.emit("audio-level", level);
                        let now = std::time::Instant::now();
                        let bands: [f32; 7] = std::array::from_fn(|index| combined_level((mic_bands.0[index], mic_bands.1), (system_bands.0[index], system_bands.1), now));
                        let _ = app_clone.emit("audio-spectrum", bands);
                    }
                    event = event_rx.recv() => match event {
                        Some(RecordingEvent::AudioLevel(level)) => mic = (level, std::time::Instant::now()),
                        Some(RecordingEvent::SystemAudioLevel(level)) => system = (level, std::time::Instant::now()),
                        Some(RecordingEvent::AudioSpectrum(bands)) => mic_bands = (bands, std::time::Instant::now()),
                        Some(RecordingEvent::SystemAudioSpectrum(bands)) => system_bands = (bands, std::time::Instant::now()),
                        Some(RecordingEvent::Stopped { .. }) => break,
                        Some(RecordingEvent::Error(error)) => {
                            // A losing callback may enqueue first; consume the atomically published winner.
                            if let Some(code) = event_terminal.take() { emit_diagnostic(&app_clone, code); }
                            if let Ok(mut state) = shared_state.lock() {
                                if state.file_path.as_ref() == Some(&session_path) { *state = RecordingState::default(); }
                            }
                            let _ = app_clone.emit("audio-level", 0.0_f32);
                            let _ = app_clone.emit("audio-spectrum", [0.0_f32; 7]);
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
            done_tx,
            Arc::clone(&terminal),
        ).map_err(|error| {
            emit_terminal(&app, &terminal, RecordingDiagnosticCode::StartFailed);
            RecordingCommandError::native_owned(error)
        })?;

        guard.terminal = Some(Arc::clone(&terminal));
        guard.cmd_tx = Some(cmd_tx);
        guard.is_recording = true;
        guard.is_paused = false;
        guard.file_path = Some(file_path.clone());
        guard.completion = Some(done_rx);

        (file_path, ready)
    };
    ready.await.map_err(|_| {
        emit_terminal(&app, &terminal, RecordingDiagnosticCode::StartFailed);
        RecordingCommandError::native_owned("Opname-thread is gestopt tijdens het starten")
    })?.map_err(RecordingCommandError::native_owned)?;
    Ok(file_path)
}

#[tauri::command]
pub async fn stop_recording(
    app: AppHandle,
    state: tauri::State<'_, SharedRecordingState>,
) -> Result<RecordingResult, RecordingCommandError> {
    let (cmd_tx, completion, file_path, terminal) = {
        let mut guard = state.lock().map_err(|e| {
            if let Some(terminal) = &e.get_ref().terminal { emit_terminal(&app, terminal, RecordingDiagnosticCode::StopFailed); }
            else { emit_diagnostic(&app, RecordingDiagnosticCode::StopFailed); }
            RecordingCommandError::native_owned(e.to_string())
        })?;
        if !guard.is_recording { return Err(RecordingCommandError::expected("Er is geen actieve opname")); }
        if guard.completion.is_none() { return Err(RecordingCommandError::expected("De opname wordt al opgeslagen")); }
        guard.is_paused = false;
        (guard.cmd_tx.take(), guard.completion.take(), guard.file_path.clone(), guard.terminal.clone())
    };
    let _ = app.emit("recording-stopping", ());
    // Every exit below must clear the session, otherwise a failed stop leaves
    // is_recording=true with no completion and blocks all later recordings.
    let result: Result<RecordingResult, String> = async {
        if let Some(tx) = cmd_tx {
            tx.send(RecordingCommand::Stop).await.map_err(|_| "Opname-thread is gestopt".to_string())?;
        }
        let completion = completion.ok_or("Opname-resultaat niet beschikbaar")?;
        // Large meetings must finish mixing before the session is cleared.
        completion.await.map_err(|_| "Opname-thread is gestopt zonder resultaat".to_string())?
    }.await;
    if result.is_err() {
        if let Some(terminal) = &terminal { emit_terminal(&app, terminal, RecordingDiagnosticCode::StopFailed); }
        else { emit_diagnostic(&app, RecordingDiagnosticCode::StopFailed); }
    }
    let mut guard = state.lock().map_err(|e| {
        if let Some(terminal) = &terminal { emit_terminal(&app, terminal, RecordingDiagnosticCode::StopFailed); }
        else { emit_diagnostic(&app, RecordingDiagnosticCode::StopFailed); }
        RecordingCommandError::native_owned(e.to_string())
    })?;
    if guard.file_path == file_path { *guard = RecordingState::default(); }
    drop(guard);
    let _ = app.emit("audio-level", 0.0_f32);
    let _ = app.emit("audio-spectrum", [0.0_f32; 7]);
    match &result {
        Ok(recording) => { let _ = app.emit("recording-stopped", recording); }
        Err(error) => { let _ = app.emit("recording-error", error); }
    }
    result.map_err(RecordingCommandError::native_owned)
}

#[tauri::command]
pub async fn pause_recording(
    app: AppHandle,
    state: tauri::State<'_, SharedRecordingState>,
) -> Result<(), RecordingCommandError> {
    let mut guard = state.lock().map_err(|e| command_failure(&app, RecordingDiagnosticCode::PauseFailed, e.to_string()))?;

    if !guard.is_recording {
        return Err(RecordingCommandError::expected("Geen actieve opname"));
    }

    if guard.is_paused {
        // Already paused — no-op is fine
        return Ok(());
    }

    if let Some(ref tx) = guard.cmd_tx {
        tx.try_send(RecordingCommand::Pause)
            .map_err(|e| command_failure(&app, RecordingDiagnosticCode::PauseFailed, format!("Pauze mislukt: {}", e)))?;
    } else {
        return Err(command_failure(&app, RecordingDiagnosticCode::PauseFailed, "Opnamekanaal is gesloten"));
    }

    // Update shared state to reflect paused status
    guard.is_paused = true;
    drop(guard);
    let _ = app.emit("recording-paused", ());

    Ok(())
}

#[tauri::command]
pub async fn resume_recording(
    app: AppHandle,
    state: tauri::State<'_, SharedRecordingState>,
) -> Result<(), RecordingCommandError> {
    let mut guard = state.lock().map_err(|e| command_failure(&app, RecordingDiagnosticCode::ResumeFailed, e.to_string()))?;

    if !guard.is_recording {
        return Err(RecordingCommandError::expected("Geen actieve opname"));
    }

    if !guard.is_paused {
        // Already recording — no-op is fine
        return Ok(());
    }

    if let Some(ref tx) = guard.cmd_tx {
        tx.try_send(RecordingCommand::Resume)
            .map_err(|e| command_failure(&app, RecordingDiagnosticCode::ResumeFailed, format!("Hervatten mislukt: {}", e)))?;
    } else {
        return Err(command_failure(&app, RecordingDiagnosticCode::ResumeFailed, "Opnamekanaal is gesloten"));
    }

    // Update shared state to reflect recording status
    guard.is_paused = false;
    drop(guard);
    let _ = app.emit("recording-resumed", ());

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
