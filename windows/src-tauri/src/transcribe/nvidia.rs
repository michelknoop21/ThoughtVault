use std::path::{Path, PathBuf};
use tauri::{AppHandle, Emitter, Manager};

pub(super) struct Model {
    pub filename: &'static str,
    pub revision: &'static str,
    pub size: u64,
    pub sha256: &'static str,
}

// Official NeMo-Speech.cpp v0.2.0 model index, pinned to its verified CPU artifacts.
pub(super) fn model(id: &str) -> Option<Model> {
    match id {
        "parakeet-tdt-0.6b-v3" => Some(Model {
            filename: "parakeet-tdt-0.6b-v3.q8_0.gguf",
            revision: "541d1f99c6b0c3cd0b11a95167540bb8edefd82b",
            size: 713975456,
            sha256: "e3880d0aaaaf2c308ea2c35016b2b895c423eb3fda924c1b463d1c19b7f4d32e",
        }),
        _ => None,
    }
}

pub(super) fn verify_model(path: &Path, model: &Model) -> Result<(), String> {
    use sha2::{Digest, Sha256};
    use std::io::Read;
    let mut file = std::fs::File::open(path).map_err(|e| e.to_string())?;
    if file.metadata().map_err(|e| e.to_string())?.len() != model.size {
        return Err("Het Parakeet-model is onvolledig. Download het model opnieuw.".into());
    }
    let mut hash = Sha256::new();
    let mut buffer = [0; 65536];
    loop {
        let count = file.read(&mut buffer).map_err(|e| e.to_string())?;
        if count == 0 { break; }
        hash.update(&buffer[..count]);
    }
    if format!("{:x}", hash.finalize()) != model.sha256 {
        return Err("De Parakeet-modelcontrole is mislukt. Download het model opnieuw.".into());
    }
    Ok(())
}

fn split_audio(path: &str, directory: &Path) -> Result<Vec<PathBuf>, String> {
    let mut reader = hound::WavReader::open(path).map_err(|e| format!("Kan audio niet lezen: {e}"))?;
    let spec = reader.spec();
    if spec.sample_rate != 16_000 || spec.channels != 1 || spec.bits_per_sample != 16 || spec.sample_format != hound::SampleFormat::Int {
        return Err("NVIDIA-transcriptie verwacht mono PCM16 audio op 16kHz".into());
    }
    let mut samples = reader.samples::<i16>();
    let mut files = Vec::new();
    while let Some(first) = samples.next() {
        let part = directory.join(format!("{:05}.wav", files.len()));
        let mut writer = hound::WavWriter::create(&part, spec).map_err(|e| e.to_string())?;
        writer.write_sample(first.map_err(|e| e.to_string())?).map_err(|e| e.to_string())?;
        for sample in samples.by_ref().take(60 * 16_000 - 1) {
            writer.write_sample(sample.map_err(|e| e.to_string())?).map_err(|e| e.to_string())?;
        }
        writer.finalize().map_err(|e| e.to_string())?;
        files.push(part);
    }
    if files.is_empty() { return Err("De opname bevat geen audio".into()); }
    Ok(files)
}

pub(super) fn run(app: AppHandle, model_path: &Path, audio: &str, request_id: &str) -> Result<String, String> {
    use std::process::{Command, Stdio};
    let runtime = app.path().resource_dir().map_err(|e| e.to_string())?
        .join("resources/nemo-speech-0.2.0/bin/nemo-speech.exe");
    if !runtime.is_file() { return Err("De NVIDIA CPU-runtime ontbreekt. Installeer de volledige Windows-update.".into()); }
    let work = tempfile::tempdir().map_err(|e| e.to_string())?;
    let inputs = work.path().join("audio");
    let outputs = work.path().join("text");
    std::fs::create_dir(&inputs).map_err(|e| e.to_string())?;
    std::fs::create_dir(&outputs).map_err(|e| e.to_string())?;
    // Bound offline attention and memory; the directory CLI loads the recognizer only once.
    let files = split_audio(audio, &inputs)?;
    let errors = work.path().join("errors.log");
    let mut command = Command::new(runtime);
    command.arg("--quiet").arg("transcribe").arg(&inputs)
        .arg("--model").arg(model_path).args(["--device", "cpu", "--format", "text", "--concurrency", "1"])
        .arg("--output-dir").arg(&outputs)
        .stdin(Stdio::null()).stdout(Stdio::null())
        .stderr(std::fs::File::create(&errors).map_err(|e| e.to_string())?);
    #[cfg(target_os = "windows")]
    {
        use std::os::windows::process::CommandExt;
        command.creation_flags(0x08000000);
    }
    let mut child = command.spawn().map_err(|e| format!("NVIDIA-runtime starten mislukt: {e}"))?;
    let mut last_completed = 0;
    let status = loop {
        match child.try_wait() {
            Ok(Some(status)) => break status,
            Ok(None) => {},
            Err(error) => {
                let _ = child.kill();
                let _ = child.wait();
                return Err(format!("NVIDIA-runtime controleren mislukt: {error}"));
            },
        }
        let completed = files.iter().filter(|file| outputs.join(file.file_name().unwrap()).with_extension("txt").is_file()).count();
        if completed != last_completed {
            last_completed = completed;
            let _ = app.emit("transcribe-progress", serde_json::json!({ "request_id": request_id, "progress": completed * 100 / files.len() }));
        }
        std::thread::sleep(std::time::Duration::from_millis(200));
    };
    if !status.success() {
        let error = std::fs::read_to_string(errors).unwrap_or_default().lines()
            .filter(|line| line.to_lowercase().contains("error") || line.to_lowercase().contains("failed"))
            .collect::<Vec<_>>().join(" ").chars().take(800).collect::<String>();
        return Err(format!("NVIDIA-transcriptie mislukt ({status}): {error}"));
    }
    let mut text = String::new();
    for file in files {
        let result = outputs.join(file.file_name().unwrap()).with_extension("txt");
        text.push_str(&std::fs::read_to_string(result).map_err(|e| format!("NVIDIA-transcriptie lezen mislukt: {e}"))?);
        text.push(' ');
    }
    let _ = app.emit("transcribe-progress", serde_json::json!({ "request_id": request_id, "progress": 100 }));
    Ok(text.trim().to_string())
}

#[cfg(test)]
mod tests {
    #[test]
    fn cached_model_rejects_truncated_and_corrupted_bytes() {
        let file = tempfile::NamedTempFile::new().unwrap();
        let model = super::Model { filename: "qa", revision: "qa", size: 3,
            sha256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad" };
        std::fs::write(file.path(), b"ab").unwrap();
        assert!(super::verify_model(file.path(), &model).is_err());
        std::fs::write(file.path(), b"abd").unwrap();
        assert!(super::verify_model(file.path(), &model).is_err());
        std::fs::write(file.path(), b"abc").unwrap();
        assert!(super::verify_model(file.path(), &model).is_ok());
    }

    #[test]
    fn minute_parts_preserve_all_pcm_and_tail() {
        let source = tempfile::NamedTempFile::new().unwrap();
        let spec = hound::WavSpec { channels: 1, sample_rate: 16000, bits_per_sample: 16, sample_format: hound::SampleFormat::Int };
        let mut writer = hound::WavWriter::create(source.path(), spec).unwrap();
        for index in 0..960017 { writer.write_sample((index % 32767) as i16).unwrap(); }
        writer.finalize().unwrap();
        let dir = tempfile::tempdir().unwrap();
        let parts = super::split_audio(source.path().to_str().unwrap(), dir.path()).unwrap();
        assert_eq!(parts.len(), 2);
        let samples: Vec<_> = parts.iter().flat_map(|part| hound::WavReader::open(part).unwrap().into_samples::<i16>().map(Result::unwrap)).collect();
        assert_eq!(samples.len(), 960017);
        assert!(samples.iter().enumerate().all(|(index, sample)| *sample == (index % 32767) as i16));
    }
}
