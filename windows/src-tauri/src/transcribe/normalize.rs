use std::path::Path;

/// Fixed gain, at most +12 dB and -1 dBFS peak. The original is never opened for writing.
pub fn prepare(source: &Path, directory: &Path, mut check: impl FnMut(f64) -> Result<(), String>) -> Result<tempfile::NamedTempFile, String> {
    let mut input = hound::WavReader::open(source).map_err(|e| e.to_string())?;
    let spec = input.spec();
    if spec.sample_format != hound::SampleFormat::Int || spec.bits_per_sample != 16 || spec.channels != 1 || spec.sample_rate != 16000 {
        return Err("Optimalisatie vereist 16 kHz mono PCM16".into());
    }
    let count = input.len().max(1) as f64;
    let mut peak = 0f64;
    for (index, sample) in input.samples::<i16>().enumerate() {
        if index % 16384 == 0 { check(index as f64 / count / 2.0)?; }
        peak = peak.max((sample.map_err(|e| e.to_string())? as f64 / 32768.0).abs());
    }
    let gain = if peak > 0.0 { 10f64.powf(12.0 / 20.0).min(10f64.powf(-1.0 / 20.0) / peak) } else { 1.0 };
    std::fs::create_dir_all(directory).map_err(|e| e.to_string())?;
    let output = tempfile::Builder::new().prefix("optimized-").suffix(".wav").tempfile_in(directory).map_err(|e| e.to_string())?;
    input.seek(0).map_err(|e| e.to_string())?;
    let mut writer = hound::WavWriter::new(output.reopen().map_err(|e| e.to_string())?, spec).map_err(|e| e.to_string())?;
    for (index, sample) in input.samples::<i16>().enumerate() {
        if index % 16384 == 0 { check(0.5 + index as f64 / count / 2.0)?; }
        let value = (sample.map_err(|e| e.to_string())? as f64 * gain).round() as i16;
        writer.write_sample(value).map_err(|e| e.to_string())?;
    }
    writer.finalize().map_err(|e| e.to_string())?;
    check(1.0)?;
    Ok(output)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn preserves_source_limits_peak_and_cleans_cancelled_copy() {
        let dir = tempfile::tempdir().unwrap();
        let source = dir.path().join("source.wav");
        let spec = hound::WavSpec { channels: 1, sample_rate: 16000, bits_per_sample: 16, sample_format: hound::SampleFormat::Int };
        for level in [0i16, 32, 8192, 32767] {
            let mut writer = hound::WavWriter::create(&source, spec).unwrap();
            for _ in 0..40001 { writer.write_sample(level).unwrap(); }
            writer.finalize().unwrap();
            let original = std::fs::read(&source).unwrap();
            let output = prepare(&source, dir.path(), |_| Ok(())).unwrap();
            let mut reader = hound::WavReader::open(output.path()).unwrap();
            assert_eq!(reader.len(), 40001);
            let expected = (level as f64 * if level == 0 { 1.0 } else { 10f64.powf(12.0/20.0).min(10f64.powf(-1.0/20.0)*32768.0/level as f64) }).round() as i16;
            assert!(reader.samples::<i16>().all(|v| v.unwrap() == expected));
            drop(reader);
            drop(output);
            assert!(prepare(&source, dir.path(), |progress| if progress > 0.5 { Err("cancelled".into()) } else { Ok(()) }).is_err());
            assert_eq!(std::fs::read(&source).unwrap(), original);
            assert_eq!(std::fs::read_dir(dir.path()).unwrap().count(), 1);
        }
    }
}
