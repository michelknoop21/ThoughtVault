//! Masked, rotating log file plus a session marker that detects crashes.
//! Directory-based helpers keep file behavior testable without global state.

use sha2::{Digest, Sha256};
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Mutex, OnceLock};
use std::time::{Duration, SystemTime};

pub const MAX_BYTES: u64 = 2_500_000;
pub const TAIL_LIMIT: u64 = 1_000_000;
pub const KEEP_ROTATED: Duration = Duration::from_secs(7 * 24 * 60 * 60);

const CURRENT: &str = "thoughtvault.log";
const ROTATED: &str = "thoughtvault.1.log";
const MARKER: &str = "session.open";
// Rotation, reads and pruning share the same files across background threads.
static LOG_LOCK: Mutex<()> = Mutex::new(());
static LOG_DIR: OnceLock<PathBuf> = OnceLock::new();
static LOG_QUEUE: OnceLock<std::sync::mpsc::SyncSender<LogEntry>> = OnceLock::new();
static SESSION_STARTED: AtomicBool = AtomicBool::new(false);
const QUEUE_CAPACITY: usize = 256;
const MAX_RUNTIME_CHARS: usize = 2_000;

enum LogEntry {
    Line(String, String, String),
    #[cfg(test)]
    Flush(std::sync::mpsc::Sender<()>),
}

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

pub fn init(dir: PathBuf) {
    LOG_DIR.get_or_init(|| {
        let _ = fs::create_dir_all(&dir);
        prune(&dir, SystemTime::now());
        let (tx, rx) = std::sync::mpsc::sync_channel(QUEUE_CAPACITY);
        let writer_dir = dir.clone();
        let writer = std::thread::Builder::new().name("applog".into()).spawn(move || {
            while let Ok(entry) = rx.recv() {
                match entry {
                    LogEntry::Line(level, category, message) => {
                        let category = scrub(&category.replace(['\r', '\n', '[', ']'], " "));
                        // Scrub before truncating so a cut cannot expose part of a path or email.
                        let category: String = category.chars().take(MAX_RUNTIME_CHARS).collect();
                        let message: String = scrub(&message).chars()
                            .take(MAX_RUNTIME_CHARS - category.chars().count()).collect();
                        let _ = append(&writer_dir, &level, &category, &message);
                    }
                    #[cfg(test)]
                    LogEntry::Flush(done) => { let _ = done.send(()); }
                }
            }
        });
        if writer.is_ok() { let _ = LOG_QUEUE.set(tx); }
        dir
    });
}

/// Audio callbacks must not wait for log-file I/O or LOG_LOCK.
pub fn write(level: &str, category: &str, message: &str) {
    if let Some(queue) = LOG_QUEUE.get() {
        let level = match level {
            "error" | "warn" | "debug" | "trace" => level,
            _ => "info",
        };
        // shortcut: a full queue drops diagnostics; use durable logging if the session marker is insufficient.
        let _ = queue.try_send(LogEntry::Line(level.into(), category.into(), message.into()));
    }
}

macro_rules! elog {
    ($($arg:tt)*) => {{
        let line = format!($($arg)*);
        eprintln!("{}", line);
        $crate::applog::write("info", "rust", &line);
    }};
}

#[tauri::command]
pub fn log_write(level: String, category: String, message: String) {
    write(&level, &category, &message);
}

#[tauri::command]
pub fn log_tail(max_bytes: u64) -> Result<String, String> {
    // Pending diagnostics may not have reached the file yet.
    match LOG_DIR.get() {
        Some(dir) => tail(dir, max_bytes).map_err(|e| e.to_string()),
        None => Ok(String::new()),
    }
}

/// Shows the current log file in Explorer (Finder during development on a Mac).
#[tauri::command]
pub fn log_reveal() -> Result<(), String> {
    let path = LOG_DIR.get().ok_or("Geen logmap")?.join(CURRENT);
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

#[tauri::command]
pub fn log_scrub(text: String) -> String {
    scrub(&text)
}

#[tauri::command]
pub fn session_begin() -> PreviousSession {
    match LOG_DIR.get() {
        Some(dir) => session_begin_once(dir, &SESSION_STARTED),
        None => PreviousSession { crashed: false, stage: None },
    }
}

#[tauri::command]
pub fn session_stage(stage: Option<String>) {
    if let Some(dir) = LOG_DIR.get() {
        let stage = stage.map(|s| scrub(&s));
        let _ = session_stage_at(dir, stage.as_deref());
    }
}

pub fn session_end() {
    // The crash marker is synchronous even when diagnostics remain queued.
    if let Some(dir) = LOG_DIR.get() {
        session_end_at(dir);
    }
}

#[cfg(test)]
#[path = "applog_tests.rs"]
mod tests;
