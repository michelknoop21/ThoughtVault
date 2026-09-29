use chrono::Utc;
use hound::WavReader;
use serde::{Deserialize, Serialize};
use std::path::Path;
use crate::audio::recorder::StreamingResampler;
use symphonia::core::audio::SampleBuffer;
use symphonia::core::codecs::DecoderOptions;
use symphonia::core::errors::Error as AudioError;
use symphonia::core::formats::FormatOptions;
use symphonia::core::io::MediaSourceStream;
use symphonia::core::meta::MetadataOptions;
use symphonia::core::probe::Hint;
use symphonia::default::{get_codecs, get_probe};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RecordingFile {
    pub path: String,
    pub filename: String,
    pub size_bytes: u64,
    pub created_at: i64,
    pub duration_seconds: Option<f64>,
}

/// Copy a chosen audio file into the existing recordings folder as the WAV
/// format already accepted by local Whisper and the saved-recordings view.
#[tauri::command]
pub async fn import_audio(source_path: String) -> Result<String, String> {
    let destination_dir = get_recordings_dir().await?;
    tokio::task::spawn_blocking(move || {
        convert_audio(Path::new(&source_path), Path::new(&destination_dir))
    })
    .await
    .map_err(|e| format!("Audio-import afgebroken: {e}"))?
}

fn convert_audio(source: &Path, destination_dir: &Path) -> Result<String, String> {
    if !source.is_file() {
        return Err("Audiobestand niet gevonden".to_string());
    }
    let extension = source.extension().and_then(|s| s.to_str()).unwrap_or("").to_lowercase();
    if !["wav", "mp3", "m4a", "mp4", "aac", "flac", "ogg"].contains(&extension.as_str()) {
        return Err("Niet-ondersteund audioformaat".to_string());
    }

    let file = std::fs::File::open(source).map_err(|e| format!("Kan audio niet openen: {e}"))?;
    let media = MediaSourceStream::new(Box::new(file), Default::default());
    let mut hint = Hint::new();
    hint.with_extension(&extension);
    let probed = get_probe()
        .format(&hint, media, &FormatOptions::default(), &MetadataOptions::default())
        .map_err(|e| format!("Kan audioformaat niet lezen: {e}"))?;
    let mut format = probed.format;
    let track = format.default_track().ok_or("Geen audiospoor gevonden")?;
    let track_id = track.id;
    let params = track.codec_params.clone();
    let mut decoder = get_codecs()
        .make(&params, &DecoderOptions::default())
        .map_err(|e| format!("Audioformaat niet ondersteund: {e}"))?;
    let mut resampler: Option<StreamingResampler> = None;

    let temp = tempfile::Builder::new()
        .prefix("import_")
        .suffix(".wav")
        .tempfile_in(destination_dir)
        .map_err(|e| format!("Kan audiobestand niet bewaren: {e}"))?
        .into_temp_path();
    let spec = hound::WavSpec {
        channels: 1,
        sample_rate: 16_000,
        bits_per_sample: 16,
        sample_format: hound::SampleFormat::Int,
    };
    let mut writer = hound::WavWriter::create(&temp, spec)
        .map_err(|e| format!("Kan WAV niet aanmaken: {e}"))?;
    let mut written = 0usize;

    loop {
        let packet = match format.next_packet() {
            Ok(packet) => packet,
            Err(AudioError::IoError(e)) if e.kind() == std::io::ErrorKind::UnexpectedEof => break,
            Err(e) => return Err(format!("Kan audio niet lezen: {e}")),
        };
        if packet.track_id() != track_id { continue; }
        let decoded = match decoder.decode(&packet) {
            Ok(decoded) => decoded,
            Err(AudioError::DecodeError(_)) => continue,
            Err(e) => return Err(format!("Kan audio niet decoderen: {e}")),
        };
        let channels = decoded.spec().channels.count();
        if channels == 0 { return Err("Geen audiokanalen gevonden".to_string()); }
        let resampler = resampler.get_or_insert_with(|| StreamingResampler::new(decoded.spec().rate, 16_000));
        let mut samples = SampleBuffer::<f32>::new(decoded.capacity() as u64, *decoded.spec());
        samples.copy_interleaved_ref(decoded);
        let mono: Vec<i16> = samples.samples().chunks_exact(channels).map(|frame| {
            let average = frame.iter().sum::<f32>() / channels as f32;
            (average.clamp(-1.0, 1.0) * i16::MAX as f32).round() as i16
        }).collect();
        for sample in resampler.process_i16(&mono) {
            writer.write_sample(sample).map_err(|e| format!("Kan WAV niet schrijven: {e}"))?;
            written += 1;
        }
    }

    if written == 0 { return Err("Audiobestand bevat geen geluid".to_string()); }
    writer.finalize().map_err(|e| format!("Kan WAV niet afsluiten: {e}"))?;
    temp.keep().map(|path| path.to_string_lossy().to_string())
        .map_err(|e| format!("Kan audiobestand niet bewaren: {e}"))
}

#[cfg(test)]
mod import_tests {
    use super::*;

    #[test]
    fn imported_stereo_wav_is_ready_for_local_whisper() {
        let dir = tempfile::tempdir().unwrap();
        let source = dir.path().join("meeting.wav");
        let spec = hound::WavSpec {
            channels: 2,
            sample_rate: 48_000,
            bits_per_sample: 16,
            sample_format: hound::SampleFormat::Int,
        };
        let mut writer = hound::WavWriter::create(&source, spec).unwrap();
        for _ in 0..48_000 {
            writer.write_sample(8_000i16).unwrap();
            writer.write_sample(4_000i16).unwrap();
        }
        writer.finalize().unwrap();

        let imported = convert_audio(&source, dir.path()).unwrap();
        let reader = hound::WavReader::open(imported).unwrap();
        assert_eq!(reader.spec().channels, 1);
        assert_eq!(reader.spec().sample_rate, 16_000);
        assert_eq!(reader.len(), 16_000);
    }

    #[test]
    fn imports_common_compressed_audio() {
        let dir = tempfile::tempdir().unwrap();
        for fixture in ["short.mp3", "short.m4a"] {
            let source = Path::new(env!("CARGO_MANIFEST_DIR"))
                .join("testdata")
                .join(fixture);
            let imported = convert_audio(&source, dir.path()).unwrap();
            let reader = hound::WavReader::open(imported).unwrap();
            assert_eq!(reader.spec().channels, 1);
            assert_eq!(reader.spec().sample_rate, 16_000);
            assert!(reader.len() > 3_000);
        }
    }
}

/// Returns the platform-appropriate recordings directory.
///
/// Windows: %LOCALAPPDATA%\nl.prezent.transcript-studio\Recordings
///   (NOT %APPDATA%/Roaming — Roaming gets pulled into OneDrive Known Folder
///    Move and Windows roaming profiles, which lock/sync 100MB+ WAV files
///    while the upload stream is reading them. That race produces truncated
///    multipart bodies and "field required" 422s on the server.)
/// macOS / Linux: same path that data_dir() returned before — local-vs-roaming
///   distinction only exists on Windows.
#[tauri::command]
pub async fn get_recordings_dir() -> Result<String, String> {
    let base = dirs::data_local_dir()
        .or_else(|| dirs::data_dir())
        .or_else(|| dirs::home_dir())
        .ok_or("Kan app-data map niet vinden")?;

    let recordings = base
        .join("nl.prezent.transcript-studio")
        .join("Recordings");

    std::fs::create_dir_all(&recordings)
        .map_err(|e| format!("Kan opnamemap niet aanmaken: {}", e))?;

    Ok(recordings.to_string_lossy().to_string())
}

/// One-time migration: move recordings from the old %APPDATA% (Roaming) location
/// to the new %LOCALAPPDATA% (Local) location. Idempotent — safe to call on every
/// startup; does nothing if the legacy folder is empty or missing.
///
/// Returns the number of files moved.
#[tauri::command]
pub async fn migrate_recordings_dir() -> Result<u32, String> {
    // Only Windows has a meaningful Roaming/Local split — on macOS/Linux both
    // dirs::data_dir() and dirs::data_local_dir() resolve to the same path.
    #[cfg(not(target_os = "windows"))]
    {
        return Ok(0);
    }

    #[cfg(target_os = "windows")]
    {
        let old_base = match dirs::data_dir() {
            Some(p) => p,
            None => return Ok(0),
        };
        let new_base = match dirs::data_local_dir() {
            Some(p) => p,
            None => return Ok(0),
        };

        if old_base == new_base {
            return Ok(0);
        }

        let old_dir = old_base.join("nl.prezent.transcript-studio").join("Recordings");
        let new_dir = new_base.join("nl.prezent.transcript-studio").join("Recordings");

        if !old_dir.exists() {
            return Ok(0);
        }

        std::fs::create_dir_all(&new_dir)
            .map_err(|e| format!("Kan nieuwe opnamemap niet aanmaken: {}", e))?;

        let mut moved = 0u32;
        for entry in std::fs::read_dir(&old_dir).map_err(|e| e.to_string())?.flatten() {
            let from = entry.path();
            if !from.is_file() {
                continue;
            }
            let filename = match from.file_name() {
                Some(n) => n.to_owned(),
                None => continue,
            };
            let to = new_dir.join(&filename);
            // Don't overwrite existing files in the new location
            if to.exists() {
                continue;
            }
            // Try rename first (fast, atomic on same volume); fall back to copy+remove
            match std::fs::rename(&from, &to) {
                Ok(()) => moved += 1,
                Err(_) => {
                    if std::fs::copy(&from, &to).is_ok() {
                        let _ = std::fs::remove_file(&from);
                        moved += 1;
                    }
                }
            }
        }

        // Best-effort cleanup of the now-empty legacy folder
        let _ = std::fs::remove_dir(&old_dir);

        eprintln!("[Filesystem] Migrated {} recording(s) from %APPDATA% to %LOCALAPPDATA%", moved);
        Ok(moved)
    }
}

#[tauri::command]
pub async fn list_recordings(directory: String) -> Result<Vec<RecordingFile>, String> {
    let path = Path::new(&directory);
    if !path.exists() {
        return Ok(Vec::new());
    }

    let mut recordings = Vec::new();

    for entry in std::fs::read_dir(path).map_err(|e| e.to_string())?.flatten() {
        let file_path = entry.path();
        if file_path.extension().and_then(|e| e.to_str()) == Some("wav") {
            let metadata = entry.metadata().map_err(|e| e.to_string())?;
            let created_at = metadata
                .created()
                .ok()
                .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
                .map(|d| d.as_secs() as i64)
                .unwrap_or(0);

            let duration_seconds = get_wav_duration(file_path.to_str().unwrap_or(""));

            recordings.push(RecordingFile {
                path: file_path.to_string_lossy().to_string(),
                filename: entry.file_name().to_string_lossy().to_string(),
                size_bytes: metadata.len(),
                created_at,
                duration_seconds,
            });
        }
    }

    recordings.sort_by(|a, b| b.created_at.cmp(&a.created_at));
    Ok(recordings)
}

#[tauri::command]
pub async fn delete_recording(file_path: String) -> Result<(), String> {
    std::fs::remove_file(&file_path).map_err(|e| e.to_string())
}

/// Delete recordings older than `max_age_days`.
/// Skips files that start with "queued_" (offline queue protection).
#[tauri::command]
pub async fn cleanup_old_recordings(directory: String, max_age_days: u32) -> Result<u32, String> {
    let path = Path::new(&directory);
    if !path.exists() {
        return Ok(0);
    }

    let cutoff = Utc::now().timestamp() - (max_age_days as i64 * 86_400);
    let mut deleted = 0u32;

    for entry in std::fs::read_dir(path).map_err(|e| e.to_string())?.flatten() {
        let file_path = entry.path();
        let filename = entry.file_name().to_string_lossy().to_string();

        // Protect queued uploads
        if filename.starts_with("queued_") {
            continue;
        }

        if file_path.extension().and_then(|e| e.to_str()) == Some("wav") {
            if let Ok(metadata) = entry.metadata() {
                let created_at = metadata
                    .created()
                    .ok()
                    .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
                    .map(|d| d.as_secs() as i64)
                    .unwrap_or(i64::MAX);

                if created_at < cutoff {
                    if std::fs::remove_file(&file_path).is_ok() {
                        deleted += 1;
                    }
                }
            }
        }
    }

    Ok(deleted)
}

/// Concatenate multiple WAV files into one output file.
/// All inputs must be 16kHz mono 16-bit PCM (matches recording spec).
#[tauri::command]
pub async fn concatenate_wav_files(
    input_paths: Vec<String>,
    output_path: String,
) -> Result<String, String> {
    if input_paths.is_empty() {
        return Err("Geen invoerbestanden opgegeven".to_string());
    }

    let spec = hound::WavSpec {
        channels: 1,
        sample_rate: 16000,
        bits_per_sample: 16,
        sample_format: hound::SampleFormat::Int,
    };

    let mut writer = hound::WavWriter::create(&output_path, spec)
        .map_err(|e| format!("Kan uitvoerbestand niet aanmaken: {}", e))?;

    let mut total_samples = 0u64;

    for input_path in &input_paths {
        let mut reader = WavReader::open(input_path)
            .map_err(|e| format!("Kan bestand niet lezen ({}): {}", input_path, e))?;

        for sample in reader.samples::<i16>() {
            let s = sample.map_err(|e| format!("Leesfout in {}: {}", input_path, e))?;
            writer.write_sample(s).map_err(|e| e.to_string())?;
            total_samples += 1;
        }
    }

    writer.finalize().map_err(|e| e.to_string())?;

    let duration = total_samples as f64 / 16000.0;
    eprintln!("[Concat] {} bestanden samengevoegd → {} ({:.1}s)", input_paths.len(), output_path, duration);

    Ok(output_path)
}

fn get_wav_duration(file_path: &str) -> Option<f64> {
    let reader = WavReader::open(file_path).ok()?;
    let spec = reader.spec();
    let num_samples = reader.len();
    Some(num_samples as f64 / spec.sample_rate as f64)
}
