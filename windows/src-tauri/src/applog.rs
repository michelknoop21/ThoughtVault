//! Masked, rotating log file plus a session marker that detects crashes.
//! All functions take the log directory so tests can run on a temp dir.

use sha2::{Digest, Sha256};
use std::fs;
use std::io::Write;
use std::path::Path;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;
use std::time::{Duration, SystemTime};

pub const MAX_BYTES: u64 = 2_500_000;
pub const TAIL_LIMIT: u64 = 1_000_000;
pub const KEEP_ROTATED: Duration = Duration::from_secs(7 * 24 * 60 * 60);

const CURRENT: &str = "thoughtvault.log";
const ROTATED: &str = "thoughtvault.1.log";
const MARKER: &str = "session.open";
// Rotation, reads and pruning share the same files across background threads.
static LOG_LOCK: Mutex<()> = Mutex::new(());

#[derive(Debug, Clone, PartialEq, serde::Serialize)]
pub struct PreviousSession {
    pub crashed: bool,
    pub stage: Option<String>,
}

/// "k-" plus the first six hex characters of the SHA-256 of `value`.
pub fn mask_token(value: &str) -> String {
    let digest = Sha256::digest(value.as_bytes());
    format!("k-{:02x}{:02x}{:02x}", digest[0], digest[1], digest[2])
}

fn is_local(c: char) -> bool {
    c.is_ascii_alphanumeric() || "._%+-".contains(c)
}

fn is_domain(c: char) -> bool {
    c.is_ascii_alphanumeric() || c == '.' || c == '-'
}

fn is_path_stop(c: char) -> bool {
    "\"'<>|()\n\r\t,;".contains(c)
}

fn is_drive_start(c: &[char], i: usize) -> bool {
    c[i].is_ascii_alphabetic()
        && c.get(i + 1) == Some(&':')
        && matches!(c.get(i + 2), Some('\\') | Some('/'))
}

/// Mask e-mail addresses and Windows paths (spaces included) in `text`.
pub fn scrub(text: &str) -> String {
    let c: Vec<char> = text.chars().collect();
    let mut out = String::with_capacity(text.len());
    let mut i = 0;
    while i < c.len() {
        let drive = is_drive_start(&c, i);
        let unc = c[i] == '\\' && c.get(i + 1) == Some(&'\\');
        if drive || unc {
            let mut end = i;
            while end < c.len() && !is_path_stop(c[end]) {
                end += 1;
            }
            while end > i && c[end - 1] == ' ' {
                end -= 1;
            }
            out.push_str(&mask_token(&c[i..end].iter().collect::<String>()));
            i = end;
        } else if is_local(c[i]) {
            let mut j = i;
            while j < c.len() && is_local(c[j]) && !is_drive_start(&c, j) {
                j += 1;
            }
            let mut k = j;
            if c.get(j) == Some(&'@') {
                k = j + 1;
                while k < c.len() && is_domain(c[k]) {
                    k += 1;
                }
            }
            if k > j + 1 && c[j + 1..k].contains(&'.') {
                out.push_str(&mask_token(&c[i..k].iter().collect::<String>()));
                i = k;
            } else {
                out.extend(&c[i..j]);
                i = j;
            }
        } else {
            out.push(c[i]);
            i += 1;
        }
    }
    out
}

pub fn append(dir: &Path, level: &str, category: &str, message: &str) -> std::io::Result<()> {
    let _guard = LOG_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    fs::create_dir_all(dir)?;
    let time = chrono::Utc::now().to_rfc3339_opts(chrono::SecondsFormat::Secs, true);
    let message = scrub(&message.replace(['\r', '\n'], " "));
    let line = format!("{time} {} [{category}] {message}\n", level.to_uppercase());
    let path = dir.join(CURRENT);
    let size = match fs::metadata(&path) {
        Ok(metadata) => metadata.len(),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => 0,
        Err(e) => return Err(e),
    };
    if size > 0 && size + line.len() as u64 > MAX_BYTES {
        fs::rename(&path, dir.join(ROTATED))?;
    }
    let mut file = fs::OpenOptions::new().create(true).append(true).open(path)?;
    file.write_all(line.as_bytes())
}

/// Last `min(max_bytes, TAIL_LIMIT)` bytes of the rotated plus current log, from a line start.
pub fn tail(dir: &Path, max_bytes: u64) -> std::io::Result<String> {
    let _guard = LOG_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    let mut data = Vec::new();
    for name in [ROTATED, CURRENT] {
        match fs::read(dir.join(name)) {
            Ok(bytes) => data.extend(bytes),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
            Err(e) => return Err(e),
        }
    }
    let limit = max_bytes.min(TAIL_LIMIT) as usize;
    let mut start = data.len().saturating_sub(limit);
    if start > 0 && data[start - 1] != b'\n' {
        start = match data[start..].iter().position(|&b| b == b'\n') {
            Some(p) => start + p + 1,
            None => data.len(),
        };
    }
    Ok(String::from_utf8_lossy(&data[start..]).into_owned())
}

/// Remove the rotated log once it is older than `KEEP_ROTATED`.
pub fn prune(dir: &Path, now: SystemTime) {
    let _guard = LOG_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    let path = dir.join(ROTATED);
    let old = fs::metadata(&path)
        .and_then(|m| m.modified())
        .ok()
        .and_then(|t| now.duration_since(t).ok())
        .is_some_and(|age| age > KEEP_ROTATED);
    if old {
        let _ = fs::remove_file(path);
    }
}

pub fn session_begin_at(dir: &Path) -> PreviousSession {
    let path = dir.join(MARKER);
    let previous = match fs::read_to_string(&path) {
        Ok(content) => {
            let stage = content.trim();
            PreviousSession { crashed: true, stage: (!stage.is_empty()).then(|| stage.to_string()) }
        }
        Err(_) => PreviousSession { crashed: path.exists(), stage: None },
    };
    let _ = fs::create_dir_all(dir);
    let _ = fs::write(path, "");
    previous
}

pub fn session_begin_once(dir: &Path, started: &AtomicBool) -> PreviousSession {
    if started.swap(true, Ordering::SeqCst) {
        PreviousSession { crashed: false, stage: None }
    } else {
        session_begin_at(dir)
    }
}

pub fn session_stage_at(dir: &Path, stage: Option<&str>) -> std::io::Result<()> {
    fs::create_dir_all(dir)?;
    fs::write(dir.join(MARKER), stage.unwrap_or(""))
}

pub fn session_end_at(dir: &Path) {
    let _ = fs::remove_file(dir.join(MARKER));
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn append_writes_level_category_and_scrubbed_message() {
        let d = tempfile::tempdir().unwrap();
        append(d.path(), "error", "Fout", r#"open "C:\Users\Jan\x.wav" mislukt"#).unwrap();
        let text = std::fs::read_to_string(d.path().join("thoughtvault.log")).unwrap();
        assert!(text.contains(" ERROR [Fout] open \"k-"));
        assert!(!text.contains("Jan"));
        assert!(text.ends_with("\" mislukt\n"));
    }

    #[test]
    fn rotates_when_the_next_line_would_exceed_the_limit() {
        let d = tempfile::tempdir().unwrap();
        std::fs::write(d.path().join("thoughtvault.log"), vec![b'a'; (MAX_BYTES - 10) as usize])
            .unwrap();
        append(d.path(), "info", "Test", "volgende regel").unwrap();
        assert_eq!(
            std::fs::metadata(d.path().join("thoughtvault.1.log")).unwrap().len(),
            MAX_BYTES - 10
        );
        assert!(std::fs::read_to_string(d.path().join("thoughtvault.log"))
            .unwrap()
            .contains("volgende regel"));
    }

    #[test]
    fn prune_removes_rotated_file_older_than_seven_days() {
        let d = tempfile::tempdir().unwrap();
        let old = d.path().join("thoughtvault.1.log");
        std::fs::write(&old, "x").unwrap();
        let now = std::time::SystemTime::now();
        std::fs::File::options()
            .write(true)
            .open(&old)
            .unwrap()
            .set_modified(now - std::time::Duration::from_secs(6 * 86_400))
            .unwrap();
        prune(d.path(), now);
        assert!(old.exists());
        std::fs::File::options()
            .write(true)
            .open(&old)
            .unwrap()
            .set_modified(now - std::time::Duration::from_secs(8 * 86_400))
            .unwrap();
        prune(d.path(), now);
        assert!(!old.exists());
    }

    #[test]
    fn tail_spans_both_files_and_starts_on_a_line_boundary() {
        let d = tempfile::tempdir().unwrap();
        let lines =
            |r: std::ops::Range<u32>| r.map(|i| format!("line-{i:04}\n")).collect::<String>(); // 10 bytes each
        std::fs::write(d.path().join("thoughtvault.1.log"), lines(0..5)).unwrap();
        std::fs::write(d.path().join("thoughtvault.log"), lines(5..10)).unwrap();
        let t = tail(d.path(), 75).unwrap();
        assert_eq!(t, lines(3..10)); // 70 bytes, the partial line before is dropped
        assert!(tail(d.path(), 10_000_000).unwrap().len() as u64 <= TAIL_LIMIT);
    }

    #[test]
    fn mask_token_is_stable_and_short() {
        let a = mask_token("Overleg Gemeente");
        assert_eq!(a, mask_token("Overleg Gemeente"));
        assert_ne!(a, mask_token("Overleg Provincie"));
        assert!(
            a.starts_with("k-") && a.len() == 8 && a[2..].chars().all(|c| c.is_ascii_hexdigit())
        );
    }

    #[test]
    fn scrub_masks_emails_and_windows_paths_with_spaces() {
        let s = scrub(r"Bestand niet gevonden: C:\Users\Jan\Documents\Overleg Gemeente.wav");
        assert!(s.starts_with("Bestand niet gevonden: k-"));
        assert!(!s.contains("Jan") && !s.contains("Overleg"));
        let q = scrub(r#"open "C:\Users\Jan\a b.wav": os error 2"#);
        assert!(q.ends_with(r#"": os error 2"#) && !q.contains("Jan"));
        let unc = scrub(r"\\server\share\Klant X\notulen.txt kon niet worden gelezen");
        assert!(!unc.contains("Klant"));
        let m = scrub("mail jan.devries@example.nl faalde");
        assert_eq!(m, format!("mail {} faalde", mask_token("jan.devries@example.nl")));
        assert_eq!(scrub("Model niet geladen na 30 s"), "Model niet geladen na 30 s");
        assert_eq!(scrub("mail a@example.com."), format!("mail {}", mask_token("a@example.com.")));
        assert_eq!(
            scrub(r"open C:\Users\Jan\x.wav mislukt"),
            format!("open {}", mask_token(r"C:\Users\Jan\x.wav mislukt"))
        );
        for path in [r"C:\Users\Jan\meeting.wav", "C:/Users/Jan/meeting.wav"] {
            assert_eq!(
                scrub(&format!("open path_{path}")),
                format!("open path_{}", mask_token(path))
            );
        }
    }

    #[test]
    fn rotation_replaces_an_existing_rotated_file() {
        let d = tempfile::tempdir().unwrap();
        fs::write(d.path().join(ROTATED), "old").unwrap();
        fs::write(d.path().join(CURRENT), vec![b'a'; MAX_BYTES as usize]).unwrap();
        append(d.path(), "info", "Test", "new").unwrap();
        assert_eq!(fs::metadata(d.path().join(ROTATED)).unwrap().len(), MAX_BYTES);
    }

    #[test]
    fn tail_ignores_missing_files_but_propagates_other_errors() {
        let d = tempfile::tempdir().unwrap();
        assert_eq!(tail(d.path(), 100).unwrap(), "");
        fs::create_dir(d.path().join(CURRENT)).unwrap();
        assert!(tail(d.path(), 100).is_err());
    }

    #[test]
    fn concurrent_appends_keep_every_line() {
        let d = tempfile::tempdir().unwrap();
        std::thread::scope(|scope| {
            for _ in 0..8 {
                scope.spawn(|| {
                    for _ in 0..20 {
                        append(d.path(), "info", "Test", "concurrent").unwrap();
                    }
                });
            }
        });
        assert_eq!(tail(d.path(), TAIL_LIMIT).unwrap().lines().count(), 160);
    }

    #[test]
    fn tail_handles_line_boundaries_zero_limits_and_unicode() {
        let d = tempfile::tempdir().unwrap();
        fs::write(d.path().join(CURRENT), "eerste\nlaatst é\n").unwrap();
        assert_eq!(tail(d.path(), "laatst é\n".len() as u64).unwrap(), "laatst é\n");
        assert_eq!(tail(d.path(), 0).unwrap(), "");
        assert_eq!(tail(d.path(), 2).unwrap(), "");
    }

    #[test]
    fn invalid_marker_still_reports_a_previous_crash() {
        let d = tempfile::tempdir().unwrap();
        fs::write(d.path().join(MARKER), [255]).unwrap();
        assert_eq!(session_begin_at(d.path()), PreviousSession { crashed: true, stage: None });
    }

    #[test]
    fn session_marker_reports_crash_with_running_stage() {
        let d = tempfile::tempdir().unwrap();
        assert_eq!(session_begin_at(d.path()), PreviousSession { crashed: false, stage: None });
        session_stage_at(d.path(), Some("transcriberen")).unwrap();
        assert_eq!(
            session_begin_at(d.path()),
            PreviousSession { crashed: true, stage: Some("transcriberen".into()) }
        );
        session_end_at(d.path());
        assert_eq!(session_begin_at(d.path()), PreviousSession { crashed: false, stage: None });
        session_stage_at(d.path(), None).unwrap();
        assert_eq!(session_begin_at(d.path()), PreviousSession { crashed: true, stage: None });
    }

    #[test]
    fn session_begin_once_reports_clean_on_later_calls() {
        let d = tempfile::tempdir().unwrap();
        std::fs::create_dir_all(d.path()).unwrap();
        std::fs::write(d.path().join("session.open"), "notule").unwrap();
        let started = std::sync::atomic::AtomicBool::new(false);
        assert_eq!(
            session_begin_once(d.path(), &started),
            PreviousSession { crashed: true, stage: Some("notule".into()) }
        );
        assert_eq!(
            session_begin_once(d.path(), &started),
            PreviousSession { crashed: false, stage: None }
        );
    }
}
