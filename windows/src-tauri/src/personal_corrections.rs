use std::{
    io::Write,
    path::{Path, PathBuf},
};
use tauri::Manager;

/// Context files kept next to the glossary; the frontend owns their JSON format.
const CONTEXT_FILES: [&str; 2] = ["context-history.json", "context-suggestions.json"];
/// History keeps up to 50 versions per item, so it may grow well past the glossary cap.
const CONTEXT_FILE_MAX_BYTES: usize = 32 * 1024 * 1024;

fn read(path: &Path) -> Result<Option<serde_json::Value>, String> {
    match std::fs::read(path) {
        Ok(bytes) => serde_json::from_slice(&bytes).map(Some).map_err(|e| format!("Woordenlijst lezen mislukt: {e}")),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(error) => Err(format!("Woordenlijst lezen mislukt: {error}")),
    }
}
fn write(path: &Path, document: &serde_json::Value) -> Result<(), String> {
    if !matches!(document.get("version").and_then(|v| v.as_u64()), Some(1 | 2)) || !document.get("entries").is_some_and(|v| v.is_array()) {
        return Err("Onbekend woordenlijstformaat".into());
    }
    let bytes = serde_json::to_vec(document).map_err(|e| e.to_string())?;
    if bytes.len() > 1_000_000 { return Err("Woordenlijst te groot".into()); }
    write_atomic(path, &bytes).map_err(|e| format!("Woordenlijst bewaren mislukt: {e}"))
}
fn write_atomic(path: &Path, bytes: &[u8]) -> Result<(), String> {
    let parent = path.parent().ok_or("Ongeldig opslagpad")?;
    std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    let mut file = tempfile::NamedTempFile::new_in(parent).map_err(|e| e.to_string())?;
    file.write_all(bytes).map_err(|e| e.to_string())?;
    file.as_file().sync_all().map_err(|e| e.to_string())?;
    file.persist(path).map_err(|e| e.to_string())?;
    Ok(())
}
fn write_context(path: &Path, contents: &str) -> Result<(), String> {
    if contents.len() > CONTEXT_FILE_MAX_BYTES { return Err("Contextbestand te groot".into()); }
    write_atomic(path, contents.as_bytes()).map_err(|e| format!("Contextbestand bewaren mislukt: {e}"))
}
fn context_path(dir: &Path, name: &str) -> Result<PathBuf, String> {
    if CONTEXT_FILES.contains(&name) { Ok(dir.join(name)) } else { Err("Onbekend contextbestand".into()) }
}
/// Raw text; None when the file does not exist. Invalid UTF-8 is read lossily so the
/// frontend sees an undecodable file and can move it aside.
fn read_text(path: &Path) -> Result<Option<String>, String> {
    match std::fs::read(path) {
        Ok(bytes) => Ok(Some(String::from_utf8_lossy(&bytes).into_owned())),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(error) => Err(format!("Contextbestand lezen mislukt: {error}")),
    }
}
/// Keeps an undecodable file for recovery under `<name>.unreadable-<suffix>`.
fn set_aside(path: &Path, suffix: &str) -> Result<(), String> {
    if suffix.is_empty() || !suffix.chars().all(|c| c.is_ascii_alphanumeric() || c == '-') {
        return Err("Ongeldige naam".into());
    }
    let mut target = path.as_os_str().to_owned();
    target.push(format!(".unreadable-{suffix}"));
    std::fs::rename(path, target).map_err(|e| format!("Contextbestand opzij zetten mislukt: {e}"))
}
fn data_dir(app: &tauri::AppHandle) -> Result<PathBuf, String> {
    app.path().app_data_dir().map_err(|e| e.to_string())
}
#[tauri::command]
pub fn load_personal_corrections(app: tauri::AppHandle) -> Result<Option<serde_json::Value>, String> {
    read(&data_dir(&app)?.join("personal-corrections.json"))
}
#[tauri::command]
pub fn save_personal_corrections(app: tauri::AppHandle, document: serde_json::Value) -> Result<(), String> {
    write(&data_dir(&app)?.join("personal-corrections.json"), &document)
}
// The context commands are async so the read, fsync and rename run off the UI thread.
#[tauri::command]
pub async fn read_context_file(app: tauri::AppHandle, name: String) -> Result<Option<String>, String> {
    read_text(&context_path(&data_dir(&app)?, &name)?)
}
#[tauri::command]
pub async fn write_context_file(app: tauri::AppHandle, name: String, contents: String) -> Result<(), String> {
    write_context(&context_path(&data_dir(&app)?, &name)?, &contents)
}
#[tauri::command]
pub async fn set_aside_context_file(app: tauri::AppHandle, name: String, suffix: String) -> Result<(), String> {
    set_aside(&context_path(&data_dir(&app)?, &name)?, &suffix)
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn replaces_atomically_and_invalid_save_keeps_previous_document() {
        let dir = tempfile::tempdir().unwrap(); let path = dir.path().join("personal-corrections.json");
        assert!(read(&path).unwrap().is_none());
        let original = serde_json::json!({"version":1,"entries":[]});
        write(&path, &original).unwrap();
        assert!(write(&path, &serde_json::json!({"version":2})).is_err());
        assert!(write(&path, &serde_json::json!({"version":3,"entries":[]})).is_err());
        assert_eq!(read(&path).unwrap().unwrap(), original);
        let next = serde_json::json!({"version":2,"entries":[{"id":"yinga"}],"dismissed":["person:jan"]});
        write(&path, &next).unwrap(); assert_eq!(read(&path).unwrap().unwrap(), next);
        assert!(write(&dir.path().join("missing").join("x"), &next).is_ok());
        assert!(write(dir.path(), &next).is_err());
    }
    #[test]
    fn context_files_are_allowlisted_and_set_aside_keeps_the_original() {
        let dir = tempfile::tempdir().unwrap();
        assert!(context_path(dir.path(), "../personal-corrections.json").is_err());
        let path = context_path(dir.path(), "context-history.json").unwrap();
        assert!(read_text(&path).unwrap().is_none());
        write_context(&path, "geen json").unwrap();
        assert!(write_context(&path, &"x".repeat(CONTEXT_FILE_MAX_BYTES + 1)).is_err());
        assert_eq!(read_text(&path).unwrap().as_deref(), Some("geen json"));
        assert!(set_aside(&path, "../x").is_err());
        set_aside(&path, "AB-12").unwrap();
        assert!(read_text(&path).unwrap().is_none());
        assert_eq!(std::fs::read_to_string(dir.path().join("context-history.json.unreadable-AB-12")).unwrap(), "geen json");
    }
}
