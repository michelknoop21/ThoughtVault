// Local speech-to-text via whisper-rs (whisper.cpp bindings).
//
// Mirrors the macOS app's WhisperKitTranscriber: a recorded 16 kHz mono WAV is
// transcribed fully on-device, no server. GGML models are downloaded on first
// use from the official whisper.cpp model repo into the app data dir.

use std::path::PathBuf;
use tauri::{AppHandle, Emitter, Manager};

/// Maps a short model id (as stored in settings) to its GGML filename.
/// Mirrors the model picker in the Windows Settings UI.
fn model_filename(model_id: &str) -> String {
    format!("ggml-{}.bin", model_id)
}

fn models_dir(app: &AppHandle) -> Result<PathBuf, String> {
    let dir = app
        .path()
        .app_data_dir()
        .map_err(|e| format!("Kan app-data map niet bepalen: {}", e))?
        .join("whisper-models");
    std::fs::create_dir_all(&dir).map_err(|e| format!("Kan modelmap niet aanmaken: {}", e))?;
    Ok(dir)
}

fn model_path(app: &AppHandle, model_id: &str) -> Result<PathBuf, String> {
    Ok(models_dir(app)?.join(model_filename(model_id)))
}

#[derive(serde::Serialize)]
pub struct WhisperModelStatus {
    pub exists: bool,
    pub path: String,
    pub size_bytes: u64,
}

/// Whether the chosen model is already downloaded, and where it lives.
#[tauri::command]
pub async fn whisper_model_status(
    app: AppHandle,
    model_id: String,
) -> Result<WhisperModelStatus, String> {
    let path = model_path(&app, &model_id)?;
    let (exists, size_bytes) = match std::fs::metadata(&path) {
        Ok(m) => (m.is_file() && m.len() > 0, m.len()),
        Err(_) => (false, 0),
    };
    Ok(WhisperModelStatus {
        exists,
        path: path.to_string_lossy().to_string(),
        size_bytes,
    })
}

/// Downloads the GGML model with progress events on `whisper-download-progress`.
/// No-op (returns immediately) if the model already exists.
#[tauri::command]
pub async fn download_whisper_model(app: AppHandle, model_id: String) -> Result<String, String> {
    use futures_util::StreamExt;
    use tokio::io::AsyncWriteExt;

    let dest = model_path(&app, &model_id)?;
    if let Ok(m) = std::fs::metadata(&dest) {
        if m.is_file() && m.len() > 0 {
            return Ok(dest.to_string_lossy().to_string());
        }
    }

    let url = format!(
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/{}",
        model_filename(&model_id)
    );

    let resp = reqwest::get(&url)
        .await
        .map_err(|e| format!("Download mislukt: {}", e))?;
    if !resp.status().is_success() {
        return Err(format!("Download mislukt: HTTP {}", resp.status()));
    }
    let total = resp.content_length().unwrap_or(0);

    // Stream to a temp file so a half-finished download never looks complete.
    let tmp = dest.with_extension("bin.part");
    let mut file = tokio::fs::File::create(&tmp)
        .await
        .map_err(|e| format!("Kan bestand niet aanmaken: {}", e))?;

    let mut downloaded: u64 = 0;
    let mut last_emit: u64 = 0;
    let mut stream = resp.bytes_stream();
    while let Some(chunk) = stream.next().await {
        let chunk = chunk.map_err(|e| format!("Downloadfout: {}", e))?;
        file.write_all(&chunk)
            .await
            .map_err(|e| format!("Schrijffout: {}", e))?;
        downloaded += chunk.len() as u64;
        // Throttle events to ~every 2 MB to avoid flooding the UI thread.
        if downloaded - last_emit >= 2_000_000 || downloaded == total {
            last_emit = downloaded;
            let pct = if total > 0 {
                (downloaded as f64 / total as f64 * 100.0).round() as u32
            } else {
                0
            };
            let _ = app.emit(
                "whisper-download-progress",
                serde_json::json!({
                    "model": model_id,
                    "downloaded": downloaded,
                    "total": total,
                    "pct": pct,
                }),
            );
        }
    }
    file.flush().await.map_err(|e| e.to_string())?;
    drop(file);

    std::fs::rename(&tmp, &dest).map_err(|e| format!("Kan model niet plaatsen: {}", e))?;
    Ok(dest.to_string_lossy().to_string())
}

/// Transcribes a recorded WAV fully on-device. Emits coarse progress (0-100) on
/// `transcribe-progress`. Returns the transcribed text (Dutch).
#[tauri::command]
pub async fn transcribe_local(
    app: AppHandle,
    file_path: String,
    model_id: String,
) -> Result<String, String> {
    let model = model_path(&app, &model_id)?;
    if !model.is_file() {
        return Err("Model nog niet gedownload".to_string());
    }

    // whisper inference is blocking + CPU-heavy: keep it off the async runtime.
    tokio::task::spawn_blocking(move || run_whisper(app, &model, &file_path))
        .await
        .map_err(|e| format!("Transcriptie-thread mislukt: {}", e))?
}

fn run_whisper(app: AppHandle, model: &PathBuf, wav_path: &str) -> Result<String, String> {
    use whisper_rs::{
        convert_integer_to_float_audio, FullParams, SamplingStrategy, WhisperContext,
        WhisperContextParameters,
    };

    // Read the recorded WAV (recorder always writes 16 kHz mono i16).
    let reader = hound::WavReader::open(wav_path)
        .map_err(|e| format!("Kan opname niet lezen: {}", e))?;
    let spec = reader.spec();
    let samples: Vec<i16> = reader
        .into_samples::<i16>()
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| format!("Kan audio niet decoderen: {}", e))?;
    if spec.sample_rate != 16000 {
        return Err(format!(
            "Opname is {}Hz, verwacht 16kHz",
            spec.sample_rate
        ));
    }
    let mut audio = vec![0.0f32; samples.len()];
    convert_integer_to_float_audio(&samples, &mut audio)
        .map_err(|e| format!("Audioconversie mislukt: {}", e))?;

    let ctx = WhisperContext::new_with_params(
        &model.to_string_lossy(),
        WhisperContextParameters::default(),
    )
    .map_err(|e| format!("Model laden mislukt: {}", e))?;
    let mut state = ctx
        .create_state()
        .map_err(|e| format!("Whisper-state mislukt: {}", e))?;

    let mut params = FullParams::new(SamplingStrategy::Greedy { best_of: 1 });
    params.set_language(Some("nl"));
    params.set_print_special(false);
    params.set_print_progress(false);
    params.set_print_realtime(false);
    params.set_print_timestamps(false);

    let app_progress = app.clone();
    params.set_progress_callback_safe(move |progress: i32| {
        let _ = app_progress.emit("transcribe-progress", progress);
    });

    state
        .full(params, &audio)
        .map_err(|e| format!("Transcriptie mislukt: {}", e))?;

    let num_segments = state
        .full_n_segments()
        .map_err(|e| format!("Segmenten lezen mislukt: {}", e))?;
    let mut text = String::new();
    for i in 0..num_segments {
        if let Ok(segment) = state.full_get_segment_text(i) {
            text.push_str(&segment);
        }
    }
    Ok(text.trim().to_string())
}
