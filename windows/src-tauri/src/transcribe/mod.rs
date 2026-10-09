// Local speech-to-text via whisper-rs (whisper.cpp bindings).
//
// Mirrors the macOS app's WhisperKitTranscriber: a recorded 16 kHz mono WAV is
// transcribed fully on-device, no server. GGML models are downloaded on first
// use from the official whisper.cpp model repo into the app data dir.

use std::path::PathBuf;
use std::sync::Mutex;
use tokio::sync::watch;

#[derive(Default)]
pub struct ModelDownloadControl {
    active: Mutex<Option<(String, watch::Sender<bool>)>>,
}
use tauri::{AppHandle, Emitter, Manager};

/// Maps a short model id (as stored in settings) to its GGML filename.
/// Mirrors the model picker in the Windows Settings UI.
fn model_filename(model_id: &str) -> Result<String, String> {
    if !matches!(model_id, "small" | "medium" | "large-v3") {
        return Err("Onbekend transcriptiemodel".to_string());
    }
    Ok(format!("ggml-{}.bin", model_id))
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
    Ok(models_dir(app)?.join(model_filename(model_id)?))
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
pub async fn download_whisper_model(
    app: AppHandle,
    model_id: String,
    control: tauri::State<'_, ModelDownloadControl>,
) -> Result<String, String> {
    use futures_util::StreamExt;
    use tokio::io::AsyncWriteExt;
    let dest = model_path(&app, &model_id)?;
    if dest.metadata().map(|m| m.is_file() && m.len() > 0).unwrap_or(false) {
        return Ok(dest.to_string_lossy().to_string());
    }
    let (cancel, mut cancelled) = watch::channel(false);
    {
        let mut active = control.active.lock().map_err(|e| e.to_string())?;
        if active.is_some() { return Err("Er wordt al een transcriptiemodel gedownload".to_string()); }
        *active = Some((model_id.clone(), cancel));
    }
    let tmp = dest.with_extension("bin.part");
    let result = async {
        let url = format!("https://huggingface.co/ggerganov/whisper.cpp/resolve/main/{}", model_filename(&model_id)?);
        let client = reqwest::Client::builder().timeout(std::time::Duration::from_secs(3600)).build().map_err(|e| e.to_string())?;
        let resp = tokio::select! {
            _ = cancelled.changed() => return Err("Download geannuleerd".to_string()),
            result = client.get(url).send() => result.map_err(|e| format!("Download mislukt: {e}"))?,
        };
        if !resp.status().is_success() { return Err(format!("Download mislukt: HTTP {}", resp.status())); }
        let total = resp.content_length().unwrap_or(0);
        let mut file = tokio::fs::File::create(&tmp).await.map_err(|e| e.to_string())?;
        let mut downloaded: u64 = 0;
        let mut last_emit: u64 = 0;
        let mut stream = resp.bytes_stream();
        loop {
            let chunk = tokio::select! {
                _ = cancelled.changed() => return Err("Download geannuleerd".to_string()),
                chunk = stream.next() => chunk,
            };
            let Some(chunk) = chunk else { break; };
            let chunk = chunk.map_err(|e| format!("Downloadfout: {e}"))?;
            file.write_all(&chunk).await.map_err(|e| e.to_string())?;
            downloaded += chunk.len() as u64;
            if downloaded - last_emit >= 2_000_000 || downloaded == total {
                last_emit = downloaded;
                let pct = if total > 0 { (downloaded as f64 / total as f64 * 100.0).round().min(100.0) as u32 } else { 0 };
                let _ = app.emit("whisper-download-progress", serde_json::json!({ "model": model_id, "downloaded": downloaded, "total": total, "pct": pct }));
            }
        }
        if downloaded == 0 || (total > 0 && downloaded != total) { return Err("Het model is niet volledig gedownload. Probeer opnieuw.".to_string()); }
        if *cancelled.borrow() { return Err("Download geannuleerd".to_string()); }
        file.flush().await.map_err(|e| e.to_string())?;
        drop(file);
        tokio::fs::rename(&tmp, &dest).await.map_err(|e| e.to_string())?;
        Ok(dest.to_string_lossy().to_string())
    }.await;
    if result.is_err() { let _ = tokio::fs::remove_file(&tmp).await; }
    *control.active.lock().map_err(|e| e.to_string())? = None;
    let _ = app.emit("whisper-download-finished", serde_json::json!({ "model": model_id, "error": result.as_ref().err() }));
    result
}

#[tauri::command]
pub fn whisper_download_status(control: tauri::State<'_, ModelDownloadControl>) -> Result<Option<String>, String> {
    Ok(control.active.lock().map_err(|e| e.to_string())?.as_ref().map(|(model, _)| model.clone()))
}

#[tauri::command]
pub async fn cancel_whisper_download(control: tauri::State<'_, ModelDownloadControl>) -> Result<(), String> {
    if let Some((_, cancel)) = control.active.lock().map_err(|e| e.to_string())?.as_ref() {
        let _ = cancel.send(true);
    }
    Ok(())
}

#[tauri::command]
pub async fn remove_whisper_model(app: AppHandle, model_id: String, control: tauri::State<'_, ModelDownloadControl>) -> Result<(), String> {
    let path = model_path(&app, &model_id)?;
    if control.active.lock().map_err(|e| e.to_string())?.is_some() { return Err("Wacht tot de download klaar is".to_string()); }
    match tokio::fs::remove_file(path).await {
        Ok(()) => Ok(()),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(e) => Err(e.to_string()),
    }
}

#[tauri::command]
pub async fn show_whisper_model(app: AppHandle, model_id: String) -> Result<(), String> {
    let path = model_path(&app, &model_id)?;
    #[cfg(target_os = "windows")]
    {
        std::process::Command::new("explorer.exe").arg(format!("/select,{}", path.display())).spawn().map_err(|e| e.to_string())?;
    }
    #[cfg(not(target_os = "windows"))]
    {
        std::process::Command::new("open").arg("-R").arg(path).spawn().map_err(|e| e.to_string())?;
    }
    Ok(())
}

/// Transcribes a recorded WAV fully on-device. Emits coarse progress (0-100) on
/// `transcribe-progress`. Returns the transcribed text (Dutch).
#[tauri::command]
pub async fn transcribe_local(
    app: AppHandle,
    file_path: String,
    model_id: String,
    vocabulary: Option<String>,
) -> Result<String, String> {
    let model = model_path(&app, &model_id)?;
    if !model.is_file() {
        return Err("Model nog niet gedownload".to_string());
    }

    let vocabulary = vocabulary.unwrap_or_default();
    // Thirty validated names of up to 120 characters also fit in UTF-8.
    if vocabulary.len() > 16_384 || vocabulary.contains('\0') { return Err("Ongeldige woordenlijst".into()); }
    // whisper inference is blocking + CPU-heavy: keep it off the async runtime.
    tokio::task::spawn_blocking(move || run_whisper(app, &model, &file_path, &vocabulary))
        .await
        .map_err(|e| format!("Transcriptie-thread mislukt: {}", e))?
}

fn run_whisper(app: AppHandle, model: &PathBuf, wav_path: &str, vocabulary: &str) -> Result<String, String> {
    use whisper_rs::{
        convert_integer_to_float_audio, FullParams, SamplingStrategy, WhisperContext,
        WhisperContextParameters,
    };

    // Read the recorded WAV (recorder always writes 16 kHz mono i16).
    let mut reader = hound::WavReader::open(wav_path)
        .map_err(|e| format!("Kan opname niet lezen: {}", e))?;
    let spec = reader.spec();
    if spec.sample_rate != 16000 {
        return Err(format!(
            "Opname is {}Hz, verwacht 16kHz",
            spec.sample_rate
        ));
    }
    let total_samples = reader.len() as usize;

    let ctx = WhisperContext::new_with_params(
        model,
        WhisperContextParameters::default(),
    )
    .map_err(|e| format!("Model laden mislukt: {}", e))?;
    let mut state = ctx
        .create_state()
        .map_err(|e| format!("Whisper-state mislukt: {}", e))?;

    // Stream-decode in ~10-minute windows so peak memory stays bounded on long
    // files: only one window (~58 MB) is materialized at a time instead of the
    // whole file (a 1h recording would be ~345 MB across the i16 + f32 buffers).
    // whisper.cpp already windows at 30s internally; text is joined.
    const CHUNK_SAMPLES: usize = 10 * 60 * 16000; // 10 min @ 16 kHz
    let total_chunks = total_samples.div_ceil(CHUNK_SAMPLES).max(1);

    let mut samples_iter = reader.samples::<i16>();
    let mut text = String::new();
    let mut int_buf: Vec<i16> = Vec::with_capacity(CHUNK_SAMPLES);
    let mut float_buf: Vec<f32> = vec![0.0; CHUNK_SAMPLES];

    for chunk_index in 0..total_chunks {
        int_buf.clear();
        for sample in samples_iter.by_ref().take(CHUNK_SAMPLES) {
            int_buf.push(sample.map_err(|e| format!("Kan audio niet decoderen: {}", e))?);
        }
        if int_buf.is_empty() {
            break;
        }
        float_buf.resize(int_buf.len(), 0.0);
        convert_integer_to_float_audio(&int_buf, &mut float_buf)
            .map_err(|e| format!("Audioconversie mislukt: {}", e))?;

        let mut params = FullParams::new(SamplingStrategy::Greedy { best_of: 1 });
        params.set_language(Some("nl"));
        if !vocabulary.is_empty() { params.set_initial_prompt(vocabulary); }
        params.set_print_special(false);
        params.set_print_progress(false);
        params.set_print_realtime(false);
        params.set_print_timestamps(false);

        // Map this chunk's 0-100 progress onto its slice of the overall bar.
        let app_progress = app.clone();
        let base = (chunk_index * 100 / total_chunks) as i32;
        let span = (100 / total_chunks) as i32;
        params.set_progress_callback_safe(move |progress: i32| {
            let overall = base + progress * span / 100;
            let _ = app_progress.emit("transcribe-progress", overall.min(100));
        });

        state
            .full(params, &float_buf)
            .map_err(|e| format!("Transcriptie mislukt: {}", e))?;

        for segment in state.as_iter() {
            text.push_str(segment.to_str().map_err(|e| format!("Segment lezen mislukt: {e}"))?);
        }
    }

    let _ = app.emit("transcribe-progress", 100);
    Ok(text.trim().to_string())
}

#[cfg(test)]
mod tests {
    #[test]
    #[ignore = "Requires THOUGHTVAULT_TEST_WHISPER_MODEL; exercised by Windows CI"]
    fn whisper_inference_cpu_smoke() {
        use whisper_rs::{FullParams, SamplingStrategy, WhisperContext, WhisperContextParameters};
        let model = std::env::var("THOUGHTVAULT_TEST_WHISPER_MODEL").expect("test model required");
        let ctx = WhisperContext::new_with_params(model, WhisperContextParameters::default()).unwrap();
        let mut state = ctx.create_state().unwrap();
        let mut params = FullParams::new(SamplingStrategy::Greedy { best_of: 1 });
        params.set_language(Some("nl"));
        params.set_print_realtime(false);
        params.set_print_progress(false);
        state.full(params, &vec![0.0; 16_000]).unwrap();
    }
}
