// Opt-in cloud speech-to-text with the user's own API key (DEC-060).
//
// Mirrors the macOS CloudAPITranscriber: the recorded 16 kHz mono WAV is cut
// into 10-minute WAV chunks (~19 MB, under the 25 MB upload limit) and each is
// POSTed to an OpenAI-compatible `{base}/v1/audio/transcriptions` endpoint.
// The API key is read from the keyring here, so it never passes through JS.

use std::io::Cursor;
use tauri::{AppHandle, Emitter};

const CHUNK_SAMPLES: usize = 10 * 60 * 16000; // 10 min @ 16 kHz

/// Only the cloud STT credentials may be sent to a user-supplied URL.
const ALLOWED_KEYS: [&str; 4] = ["openai_api_key", "groq_api_key", "openrouter_api_key", "custom_stt_api_key"];

/// Accepts a base with or without a trailing `/v1`.
fn endpoint(base_url: &str) -> Result<String, String> {
    let mut base = base_url.trim().trim_end_matches('/');
    base = base.strip_suffix("/v1").unwrap_or(base);
    if !(base.starts_with("https://") || base.starts_with("http://")) {
        return Err("Ongeldig adres voor cloud-transcriptie".into());
    }
    Ok(format!("{base}/v1/audio/transcriptions"))
}

/// Splits a 16 kHz mono 16-bit WAV into in-memory WAV files of at most 10 minutes.
// ponytail: all chunks are held in memory (~115 MB for 1 h); stream per chunk if hours-long files become common.
fn split_wav(path: &str) -> Result<Vec<Vec<u8>>, String> {
    let mut reader = hound::WavReader::open(path).map_err(|e| format!("Kan opname niet lezen: {e}"))?;
    let spec = reader.spec();
    if spec.sample_rate != 16000 || spec.channels != 1 || spec.bits_per_sample != 16 {
        return Err(format!("Opname is {} Hz/{} kanalen, verwacht 16 kHz mono", spec.sample_rate, spec.channels));
    }
    let mut samples = reader.samples::<i16>();
    let mut chunks = Vec::new();
    loop {
        let mut cursor = Cursor::new(Vec::new());
        let mut writer = hound::WavWriter::new(&mut cursor, spec).map_err(|e| e.to_string())?;
        let mut written = 0;
        for sample in samples.by_ref().take(CHUNK_SAMPLES) {
            writer.write_sample(sample.map_err(|e| format!("Kan audio niet decoderen: {e}"))?).map_err(|e| e.to_string())?;
            written += 1;
        }
        writer.finalize().map_err(|e| e.to_string())?;
        if written == 0 { break; }
        chunks.push(cursor.into_inner());
        if written < CHUNK_SAMPLES { break; }
    }
    Ok(chunks)
}

fn error_message(status: u16, body: &[u8]) -> String {
    if status == 401 { return "API-sleutel ongeldig".into(); }
    let detail = serde_json::from_slice::<serde_json::Value>(body).ok()
        .and_then(|v| v["error"]["message"].as_str().map(str::to_string))
        .unwrap_or_else(|| String::from_utf8_lossy(&body[..body.len().min(300)]).into_owned());
    format!("Aanbieder gaf fout {status}: {detail}")
}

/// Transcribes a recorded WAV via a cloud API. Emits progress (0-100) on
/// `transcribe-progress` like `transcribe_local`.
#[tauri::command]
pub async fn transcribe_cloud(
    app: AppHandle,
    file_path: String,
    base_url: String,
    model: String,
    credential_key: String,
    vocabulary: Option<String>,
) -> Result<String, String> {
    if !ALLOWED_KEYS.contains(&credential_key.as_str()) { return Err("Onbekende sleutel".into()); }
    let api_key = crate::commands::auth::load_credential(credential_key).await?
        .filter(|k| !k.trim().is_empty())
        .ok_or("Geen API-sleutel ingesteld voor cloud-transcriptie")?;
    let url = endpoint(&base_url)?;
    if model.trim().is_empty() { return Err("Geen model ingesteld voor cloud-transcriptie".into()); }
    let prompt = vocabulary.filter(|v| !v.trim().is_empty()).map(|v| format!("Namen en termen: {v}."));

    let chunks = tokio::task::spawn_blocking(move || split_wav(&file_path))
        .await
        .map_err(|e| format!("Audio splitsen mislukt: {e}"))??;
    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(600))
        .build()
        .map_err(|e| e.to_string())?;

    let total = chunks.len();
    let mut parts = Vec::with_capacity(total);
    for (index, chunk) in chunks.into_iter().enumerate() {
        let file = reqwest::multipart::Part::bytes(chunk).file_name("audio.wav").mime_str("audio/wav").map_err(|e| e.to_string())?;
        let mut form = reqwest::multipart::Form::new()
            .text("model", model.clone())
            .text("language", "nl")
            .text("response_format", "json")
            .part("file", file);
        if let Some(p) = &prompt { form = form.text("prompt", p.clone()); }

        let response = client.post(&url).bearer_auth(&api_key).multipart(form).send().await
            .map_err(|e| format!("Cloud-transcriptie niet bereikbaar: {e}"))?;
        let status = response.status().as_u16();
        let body = response.bytes().await.map_err(|e| e.to_string())?;
        if !(200..300).contains(&status) { return Err(error_message(status, &body)); }
        let text = serde_json::from_slice::<serde_json::Value>(&body).ok()
            .and_then(|v| v["text"].as_str().map(str::to_string))
            .ok_or("Onverwacht antwoord van de cloud-transcriptie")?;
        parts.push(text);
        let _ = app.emit("transcribe-progress", ((index + 1) * 100 / total) as i32);
    }
    Ok(parts.join(" ").trim().to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn twenty_five_minutes_split_into_three_chunks_under_upload_limit() {
        let path = std::env::temp_dir().join(format!("cloud-split-{}.wav", std::process::id()));
        let spec = hound::WavSpec { channels: 1, sample_rate: 16000, bits_per_sample: 16, sample_format: hound::SampleFormat::Int };
        let mut writer = hound::WavWriter::create(&path, spec).unwrap();
        for _ in 0..25 * 60 * 16000 { writer.write_sample(0i16).unwrap(); }
        writer.finalize().unwrap();

        let chunks = split_wav(path.to_str().unwrap()).unwrap();
        std::fs::remove_file(&path).ok();
        assert_eq!(chunks.len(), 3);
        assert!(chunks.iter().all(|c| c.len() < 25 * 1024 * 1024));
        let last = hound::WavReader::new(Cursor::new(&chunks[2])).unwrap();
        assert_eq!(last.len() as usize, 5 * 60 * 16000);
    }

    #[test]
    fn endpoint_accepts_base_with_or_without_v1() {
        assert_eq!(endpoint("https://api.groq.com/openai").unwrap(), "https://api.groq.com/openai/v1/audio/transcriptions");
        assert_eq!(endpoint("https://x.test/v1/").unwrap(), "https://x.test/v1/audio/transcriptions");
        assert_eq!(endpoint("https://openrouter.ai/api/v1").unwrap(), "https://openrouter.ai/api/v1/audio/transcriptions");
        assert!(endpoint("ftp://x").is_err());
    }

    #[test]
    fn unauthorized_maps_to_dutch_key_error() {
        assert_eq!(error_message(401, b"{}"), "API-sleutel ongeldig");
        assert_eq!(error_message(429, br#"{"error":{"message":"Rate limit"}}"#), "Aanbieder gaf fout 429: Rate limit");
    }
}
