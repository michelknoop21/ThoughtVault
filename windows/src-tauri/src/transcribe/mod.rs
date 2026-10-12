// Local speech-to-text via whisper-rs (whisper.cpp bindings).
//
// Mirrors the macOS app's WhisperKitTranscriber: a recorded 16 kHz mono WAV is
// transcribed fully on-device, no server. GGML models are downloaded on first
// use from the official whisper.cpp model repo into the app data dir.

use std::path::PathBuf;
use std::sync::Mutex;
use tokio::sync::watch;
mod nvidia;

// Keep simultaneous imports from loading multiple CPU-heavy Whisper contexts.
static TRANSCRIPTION_LOCK: Mutex<()> = Mutex::new(());

#[derive(Default)]
pub struct ModelDownloadControl {
    active: Mutex<Option<(String, watch::Sender<bool>)>>,
}
use tauri::{AppHandle, Emitter, Manager};

/// Maps a short model id (as stored in settings) to its GGML filename.
/// Mirrors the model picker in the Windows Settings UI.
fn model_filename(model_id: &str) -> Result<String, String> {
    if let Some(model) = nvidia::model(model_id) { return Ok(model.filename.into()); }
    if !matches!(model_id, "base" | "small" | "medium" | "large-v3") {
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
        Ok(m) => (m.is_file() && nvidia::model(&model_id).map_or(m.len() > 0, |model| m.len() == model.size), m.len()),
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
    use sha2::{Digest, Sha256};
    use tokio::io::AsyncWriteExt;
    let dest = model_path(&app, &model_id)?;
    if dest.metadata().map(|m| m.is_file() && m.len() > 0).unwrap_or(false) {
        if let Some(model) = nvidia::model(&model_id) { nvidia::verify_model(&dest, &model)?; }
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
        let nvidia_model = nvidia::model(&model_id);
        let url = if let Some(model) = &nvidia_model {
            format!("https://huggingface.co/nvidia/{model_id}/resolve/{}/{}", model.revision, model.filename)
        } else {
            format!("https://huggingface.co/ggerganov/whisper.cpp/resolve/main/{}", model_filename(&model_id)?)
        };
        let client = reqwest::Client::builder().timeout(std::time::Duration::from_secs(3600)).build().map_err(|e| e.to_string())?;
        let resp = tokio::select! {
            _ = cancelled.changed() => return Err("Download geannuleerd".to_string()),
            result = client.get(url).send() => result.map_err(|e| format!("Download mislukt: {e}"))?,
        };
        if !resp.status().is_success() { return Err(format!("Download mislukt: HTTP {}", resp.status())); }
        let total = resp.content_length().unwrap_or(0);
        let mut file = tokio::fs::File::create(&tmp).await.map_err(|e| e.to_string())?;
        let mut downloaded: u64 = 0;
        let mut hash = Sha256::new();
        let mut last_emit: u64 = 0;
        let mut stream = resp.bytes_stream();
        loop {
            let chunk = tokio::select! {
                _ = cancelled.changed() => return Err("Download geannuleerd".to_string()),
                chunk = stream.next() => chunk,
            };
            let Some(chunk) = chunk else { break; };
            let chunk = chunk.map_err(|e| format!("Downloadfout: {e}"))?;
            if nvidia_model.is_some() { hash.update(&chunk); }
            file.write_all(&chunk).await.map_err(|e| e.to_string())?;
            downloaded += chunk.len() as u64;
            if downloaded - last_emit >= 2_000_000 || downloaded == total {
                last_emit = downloaded;
                let pct = if total > 0 { (downloaded as f64 / total as f64 * 100.0).round().min(100.0) as u32 } else { 0 };
                let _ = app.emit("whisper-download-progress", serde_json::json!({ "model": model_id, "downloaded": downloaded, "total": total, "pct": pct }));
            }
        }
        if downloaded == 0 || (total > 0 && downloaded != total) { return Err("Het model is niet volledig gedownload. Probeer opnieuw.".to_string()); }
        if let Some(model) = nvidia_model {
            if downloaded != model.size || format!("{:x}", hash.finalize()) != model.sha256 {
                return Err("De NVIDIA-modelcontrole is mislukt. Probeer opnieuw.".into());
            }
        }
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
    request_id: String,
) -> Result<String, String> {
    let model = model_path(&app, &model_id)?;
    if !model.is_file() {
        return Err("Model nog niet gedownload".to_string());
    }

    let vocabulary = vocabulary.unwrap_or_default();
    // Thirty validated names of up to 120 characters also fit in UTF-8.
    if vocabulary.len() > 16_384 || vocabulary.contains('\0') { return Err("Ongeldige woordenlijst".into()); }
    // whisper inference is blocking + CPU-heavy: keep it off the async runtime.
    tokio::task::spawn_blocking(move || {
        let _guard = TRANSCRIPTION_LOCK.lock().map_err(|e| format!("Transcriptiewachtrij mislukt: {e}"))?;
        let result = if let Some(info) = nvidia::model(&model_id) {
            nvidia::verify_model(&model, &info).and_then(|_| nvidia::run(app, &model, &file_path, &request_id))
        } else {
            run_whisper(app, &model, &file_path, &vocabulary, &request_id)
        };
        if let Err(error) = &result { eprintln!("[transcribe_local] {error}"); }
        result
    })
        .await
        .map_err(|e| format!("Transcriptie-thread mislukt: {}", e))?
}

fn speech_detector() -> Result<(tempfile::NamedTempFile, whisper_rs::WhisperVadContext), String> {
    use std::io::Write;
    let mut file = tempfile::NamedTempFile::new().map_err(|e| e.to_string())?;
    file.write_all(include_bytes!("../../resources/vad/ggml-silero-v5.1.2.bin")).map_err(|e| e.to_string())?;
    let mut params = whisper_rs::WhisperVadContextParams::new();
    params.set_use_gpu(false);
    // Small sequential VAD frames do not benefit from CPU thread synchronization.
    params.set_n_threads(1);
    let detector = whisper_rs::WhisperVadContext::new(&file.path().to_string_lossy(), params)
        .map_err(|e| format!("Spraakdetectie laden mislukt: {e}"))?;
    Ok((file, detector))
}

fn speech_ranges(detector: &mut whisper_rs::WhisperVadContext, samples: &[f32]) -> Result<Vec<std::ops::Range<usize>>, String> {
    let mut params = whisper_rs::WhisperVadParams::new();
    params.set_speech_pad(300);
    params.set_max_speech_duration(29.4);
    let segments = detector.segments_from_samples(params, samples).map_err(|e| format!("Spraakdetectie mislukt: {e}"))?;
    let mut ranges: Vec<std::ops::Range<usize>> = Vec::new();
    for segment in segments {
        let start = ((segment.start * 160.0) as usize).min(samples.len());
        let end = ((segment.end * 160.0).ceil() as usize).min(samples.len());
        if start >= end { continue; }
        if let Some(last) = ranges.last_mut() {
            if start <= last.end + 16_000 && end - last.start <= 30 * 16_000 {
                last.end = last.end.max(end);
                continue;
            }
        }
        ranges.push(start..end);
    }
    Ok(ranges)
}

fn run_whisper(app: AppHandle, model: &PathBuf, wav_path: &str, vocabulary: &str, request_id: &str) -> Result<String, String> {
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
    let (_vad_file, mut detector) = speech_detector()?;

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

        // Long silence can trap Whisper in repetition; decode bounded speech only.
        // whisper-rs calls full_with_state, which bypasses whisper.cpp's built-in VAD.
        for range in speech_ranges(&mut detector, &float_buf)? {
            let start = chunk_index * CHUNK_SAMPLES + range.start;
            let end = chunk_index * CHUNK_SAMPLES + range.end;
            let mut params = FullParams::new(SamplingStrategy::Greedy { best_of: 1 });
            params.set_language(Some("nl"));
            params.set_no_context(true);
            if !vocabulary.is_empty() { params.set_initial_prompt(vocabulary); }
            params.set_print_special(false);
            params.set_print_progress(false);
            params.set_print_realtime(false);
            params.set_print_timestamps(false);

            // Map this chunk's 0-100 progress onto its slice of the overall bar.
            let app_progress = app.clone();
            let progress_request_id = request_id.to_string();
            params.set_progress_callback_safe(move |progress: i32| {
                let position = start + (end - start) * progress.clamp(0, 100) as usize / 100;
                let overall = position * 100 / total_samples.max(1);
                let _ = app_progress.emit("transcribe-progress", serde_json::json!({ "request_id": progress_request_id, "progress": overall.min(100) }));
            });

            state
                .full(params, &float_buf[range])
                .map_err(|e| format!("Transcriptie mislukt bij {}s: {}", start / 16_000, e))?;

            for segment in state.as_iter() {
                let bytes = segment.to_bytes().map_err(|e| format!("Segment lezen mislukt bij {}s: {e}", start / 16_000))?;
                text.push_str(&decode_whisper_text(bytes, start / 16_000));
            }
            text.push(' ');
        }
    }

    let _ = app.emit("transcribe-progress", serde_json::json!({ "request_id": request_id, "progress": 100 }));
    Ok(text.trim().to_string())
}

fn decode_whisper_text(bytes: &[u8], offset_seconds: usize) -> std::borrow::Cow<'_, str> {
    // Whisper may emit incomplete UTF-8; retain surrounding speech instead of failing the recording.
    if let Err(error) = std::str::from_utf8(bytes) {
        eprintln!("Whisper invalid UTF-8 repaired at {offset_seconds}s: {error}");
    }
    String::from_utf8_lossy(bytes)
}

#[cfg(test)]
mod tests {
    #[test]
    fn model_files_include_base_and_reject_paths() {
        for model in ["base", "small", "medium", "large-v3"] {
            assert_eq!(super::model_filename(model).unwrap(), format!("ggml-{model}.bin"));
        }
        assert!(super::model_filename("../base").is_err());
        for model in ["parakeet-tdt-0.6b-v3"] {
            assert_eq!(super::model_filename(model).unwrap(), format!("{model}.q8_0.gguf"));
        }
        assert!(super::model_filename("../parakeet-tdt-0.6b-v3").is_err());
    }

    #[test]
    fn malformed_whisper_text_preserves_surrounding_words() {
        assert_eq!(super::decode_whisper_text(b" Alex \xff maandag", 390), " Alex \u{fffd} maandag");
        assert_eq!(super::decode_whisper_text(" Caf\u{e9} maandag".as_bytes(), 390), " Caf\u{e9} maandag");
    }

    #[test]
    fn speech_detection_ignores_silence() {
        let (_file, mut detector) = super::speech_detector().unwrap();
        assert!(super::speech_ranges(&mut detector, &vec![0.0; 32_000]).unwrap().is_empty());
    }

    #[test]
    #[ignore = "Requires THOUGHTVAULT_TEST_WHISPER_MODEL; exercised by Windows CI"]
    fn whisper_inference_cpu_long_silence() {
        use whisper_rs::{FullParams, SamplingStrategy, WhisperContext, WhisperContextParameters};
        let model = std::env::var("THOUGHTVAULT_TEST_WHISPER_MODEL").unwrap();
        let ctx = WhisperContext::new_with_params(model, WhisperContextParameters::default()).unwrap();
        let mut state = ctx.create_state().unwrap();
        let mut reader = hound::WavReader::new(std::io::Cursor::new(include_bytes!("../../tests/fixtures/dutch-qa.wav"))).unwrap();
        let fixture: Vec<f32> = reader.samples::<i16>().map(|s| s.unwrap() as f32 / 32768.0).collect();
        let mut samples = vec![0.0; 32 * 16_000];
        samples.extend(&fixture);
        samples.extend(vec![0.0; 45 * 16_000]);
        samples.extend(fixture.iter().map(|sample| sample * 0.04));
        samples.extend(vec![0.0; 20 * 16_000]);
        let (_file, mut detector) = super::speech_detector().unwrap();
        let detection_started = std::time::Instant::now();
        let ranges = super::speech_ranges(&mut detector, &samples).unwrap();
        assert!(detection_started.elapsed().as_secs() < 60, "VAD must process this two-minute fixture faster than realtime");
        assert!(!ranges.is_empty());
        assert!(ranges.iter().all(|range| range.len() <= 30 * 16_000));
        let speech_samples: usize = ranges.iter().map(|range| range.len()).sum();
        let segment_count = ranges.len();
        let inference_started = std::time::Instant::now();
        let mut text = String::new();
        for range in ranges {
            let mut params = FullParams::new(SamplingStrategy::Greedy { best_of: 1 });
            params.set_language(Some("nl"));
            params.set_no_context(true);
            params.set_print_realtime(false);
            params.set_print_progress(false);
            state.full(params, &samples[range]).unwrap();
            for segment in state.as_iter() { text.push_str(&super::decode_whisper_text(segment.to_bytes().unwrap(), 0)); }
        }
        eprintln!("QA_WHISPER segments={segment_count} speech_seconds={:.2} inference_seconds={:.2}", speech_samples as f64 / 16_000.0, inference_started.elapsed().as_secs_f64());
        let lower = text.to_lowercase();
        assert_eq!(lower.matches("alex").count(), 2, "Both normal and quiet speech must survive: {text}");
        assert_eq!(lower.matches("maandag").count(), 2, "Both decisions must survive: {text}");
        assert!(!lower.contains("ik ben blij"), "No silence hallucination: {text}");
    }

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
