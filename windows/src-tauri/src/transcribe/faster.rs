use std::path::{Path, PathBuf};
use sha2::{Digest, Sha256};
use tauri::{AppHandle, Emitter, Manager};
use tokio::sync::watch;

pub(super) const MODEL_ID: &str = "faster-whisper-small";
const REVISION: &str = "536b0662742c02347bc0e980a01041f333bce120";
const FILES: &[(&str, u64, &str)] = &[
    ("config.json", 2370, "b55496ac7940a7ae47d2c01eab40edfd8701feec1229d9cce3b40014383fb828"),
    ("model.bin", 483546902, "3e305921506d8872816023e4c273e75d2419fb89b24da97b4fe7bce14170d671"),
    ("tokenizer.json", 2203239, "fb7b63191e9bb045082c79fd742a3106a12c99513ab30df4a0d47fa6cb6fd0ab"),
    ("vocabulary.txt", 459861, "34ce3fe1c5041027b3f8d42912270993f986dbc4bb34cf27f951e34a1e453913"),
];

pub(super) fn status(path: &Path) -> (bool, u64) {
    let mut total = 0;
    let mut ready = true;
    for (name, size, _) in FILES {
        let length = path.join(name).metadata().ok().filter(|m| m.is_file()).map(|m| m.len()).unwrap_or(0);
        total += length;
        ready &= length == *size;
    }
    (ready, total)
}

fn verify(path: &Path) -> Result<(), String> {
    use std::io::Read;
    for (name, size, expected) in FILES {
        let mut file = std::fs::File::open(path.join(name)).map_err(|e| format!("Faster Whisper-model ontbreekt: {e}"))?;
        if file.metadata().map_err(|e| e.to_string())?.len() != *size { return Err("Faster Whisper-model is onvolledig. Download opnieuw.".into()); }
        let mut hash = Sha256::new();
        let mut buffer = [0; 65536];
        loop {
            let count = file.read(&mut buffer).map_err(|e| e.to_string())?;
            if count == 0 { break; }
            hash.update(&buffer[..count]);
        }
        if format!("{:x}", hash.finalize()) != *expected { return Err("Faster Whisper-modelcontrole mislukt. Download opnieuw.".into()); }
    }
    Ok(())
}

pub(super) async fn download(app: &AppHandle, dest: &Path, cancelled: &mut watch::Receiver<bool>) -> Result<String, String> {
    use futures_util::StreamExt;
    use tokio::io::AsyncWriteExt;
    if status(dest).0 && verify(dest).is_ok() { return Ok(dest.to_string_lossy().into()); }
    let staging = dest.with_extension("part");
    tokio::fs::create_dir_all(&staging).await.map_err(|e| e.to_string())?;
    let client = reqwest::Client::builder().timeout(std::time::Duration::from_secs(3600)).build().map_err(|e| e.to_string())?;
    let total: u64 = FILES.iter().map(|(_, size, _)| size).sum();
    let mut downloaded = 0u64;
    let result = async {
        for (name, size, expected) in FILES {
            let url = format!("https://huggingface.co/Systran/faster-whisper-small/resolve/{REVISION}/{name}");
            let response = tokio::select! {
                _ = cancelled.changed() => return Err("Download geannuleerd".to_string()),
                response = client.get(url).send() => response.map_err(|e| e.to_string())?,
            };
            if !response.status().is_success() { return Err(format!("Download mislukt: HTTP {}", response.status())); }
            let mut file = tokio::fs::File::create(staging.join(name)).await.map_err(|e| e.to_string())?;
            let mut stream = response.bytes_stream();
            let mut hash = Sha256::new();
            let mut count = 0u64;
            let mut last_emit = downloaded;
            loop {
                let chunk = tokio::select! {
                    _ = cancelled.changed() => return Err("Download geannuleerd".to_string()),
                    chunk = stream.next() => chunk,
                };
                let Some(chunk) = chunk else { break; };
                let chunk = chunk.map_err(|e| e.to_string())?;
                count += chunk.len() as u64;
                if count > *size { return Err("Faster Whisper-model heeft een onjuiste grootte".into()); }
                hash.update(&chunk);
                file.write_all(&chunk).await.map_err(|e| e.to_string())?;
                downloaded += chunk.len() as u64;
                if downloaded - last_emit >= 2_000_000 || count == *size {
                    last_emit = downloaded;
                    let _ = app.emit("whisper-download-progress", serde_json::json!({"model": MODEL_ID, "downloaded": downloaded, "total": total, "pct": downloaded * 100 / total}));
                }
            }
            file.flush().await.map_err(|e| e.to_string())?;
            if count != *size || format!("{:x}", hash.finalize()) != *expected { return Err("Faster Whisper-modelcontrole mislukt".into()); }
        }
        if *cancelled.borrow() { return Err("Download geannuleerd".into()); }
        // Only replace this engine's cache after the entire pinned model verifies.
        if dest.exists() { tokio::fs::remove_dir_all(dest).await.map_err(|e| e.to_string())?; }
        tokio::fs::rename(&staging, dest).await.map_err(|e| e.to_string())?;
        Ok(dest.to_string_lossy().into())
    }.await;
    if result.is_err() { let _ = tokio::fs::remove_dir_all(&staging).await; }
    result
}

pub(super) fn run(app: AppHandle, model: &Path, audio: &str, vocabulary: &str, request_id: &str) -> Result<String, String> {
    use std::io::{BufRead, BufReader};
    use std::process::{Command, Stdio};
    verify(model)?;
    let runtime = app.path().resource_dir().map_err(|e| e.to_string())?
        .join("resources/faster-whisper-1.2.1/faster-whisper/faster-whisper.exe");
    if !runtime.is_file() { return Err("De Faster Whisper-runtime ontbreekt. Installeer de volledige Windows-update.".into()); }
    let work = tempfile::tempdir().map_err(|e| e.to_string())?;
    let output: PathBuf = work.path().join("result.txt");
    let mut command = Command::new(runtime);
    command.arg("--model").arg(model).arg("--audio").arg(audio).arg("--output").arg(&output)
        .arg("--vocabulary").arg(vocabulary).env("HF_HUB_OFFLINE", "1")
        .stdin(Stdio::null()).stdout(Stdio::piped()).stderr(Stdio::null());
    #[cfg(target_os = "windows")]
    {
        use std::os::windows::process::CommandExt;
        command.creation_flags(0x08000000);
    }
    eprintln!("[transcribe_local] engine=faster-whisper version=1.2.1 device=cpu compute=int8");
    let mut child = command.spawn().map_err(|e| format!("Faster Whisper starten mislukt: {e}"))?;
    for line in BufReader::new(child.stdout.take().unwrap()).lines() {
        let Ok(line) = line else { let _ = child.kill(); let _ = child.wait(); return Err("Faster Whisper-voortgang lezen mislukt".into()); };
        if let Ok(progress) = serde_json::from_str::<serde_json::Value>(&line) {
            if let Some(pct) = progress["progress"].as_u64() {
                let _ = app.emit("transcribe-progress", serde_json::json!({"request_id": request_id, "progress": pct.min(100)}));
            }
        }
    }
    let status = child.wait().map_err(|e| e.to_string())?;
    if !status.success() { return Err(format!("Faster Whisper-transcriptie mislukt ({status}). Controleer model en beschikbaar geheugen.")); }
    std::fs::read_to_string(output).map_err(|e| format!("Faster Whisper-resultaat lezen mislukt: {e}"))
}

#[cfg(test)]
mod tests {
    #[test]
    fn incomplete_or_corrupt_cache_is_not_usable() {
        let dir = tempfile::tempdir().unwrap();
        assert_eq!(super::status(dir.path()), (false, 0));
        std::fs::write(dir.path().join("config.json"), b"bad").unwrap();
        assert!(!super::status(dir.path()).0);
        assert!(super::verify(dir.path()).is_err());
    }
}
