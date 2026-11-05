use std::{io::Write, path::Path};
use tauri::Manager;

fn read(path: &Path) -> Result<Option<serde_json::Value>, String> {
    match std::fs::read(path) {
        Ok(bytes) => serde_json::from_slice(&bytes).map(Some).map_err(|e| format!("Woordenlijst lezen mislukt: {e}")),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(error) => Err(format!("Woordenlijst lezen mislukt: {error}")),
    }
}
fn write(path: &Path, document: &serde_json::Value) -> Result<(), String> {
    if document.get("version").and_then(|v| v.as_u64()) != Some(1) || !document.get("entries").is_some_and(|v| v.is_array()) {
        return Err("Onbekend woordenlijstformaat".into());
    }
    let bytes = serde_json::to_vec(document).map_err(|e| e.to_string())?;
    if bytes.len() > 1_000_000 { return Err("Woordenlijst te groot".into()); }
    let parent = path.parent().ok_or("Ongeldig opslagpad")?;
    std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    let mut file = tempfile::NamedTempFile::new_in(parent).map_err(|e| e.to_string())?;
    file.write_all(&bytes).map_err(|e| e.to_string())?;
    file.as_file().sync_all().map_err(|e| e.to_string())?;
    file.persist(path).map_err(|e| format!("Woordenlijst bewaren mislukt: {e}"))?;
    Ok(())
}
#[tauri::command]
pub fn load_personal_corrections(app: tauri::AppHandle) -> Result<Option<serde_json::Value>, String> {
    read(&app.path().app_data_dir().map_err(|e| e.to_string())?.join("personal-corrections.json"))
}
#[tauri::command]
pub fn save_personal_corrections(app: tauri::AppHandle, document: serde_json::Value) -> Result<(), String> {
    write(&app.path().app_data_dir().map_err(|e| e.to_string())?.join("personal-corrections.json"), &document)
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
        assert_eq!(read(&path).unwrap().unwrap(), original);
        let next = serde_json::json!({"version":1,"entries":[{"id":"yinga"}]});
        write(&path, &next).unwrap(); assert_eq!(read(&path).unwrap().unwrap(), next);
        assert!(write(&dir.path().join("missing").join("x"), &next).is_ok());
        assert!(write(dir.path(), &next).is_err());
    }
}
