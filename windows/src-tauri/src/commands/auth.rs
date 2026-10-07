use keyring::Entry;

const SERVICE_NAME: &str = "nl.prezent.transcript-studio";

#[tauri::command]
pub async fn store_credential(key: String, value: String) -> Result<(), String> {
    let entry = Entry::new(SERVICE_NAME, &key).map_err(|e| e.to_string())?;
    entry.set_password(&value).map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn load_credential(key: String) -> Result<Option<String>, String> {
    let entry = Entry::new(SERVICE_NAME, &key).map_err(|e| e.to_string())?;
    match entry.get_password() {
        Ok(value) => Ok(Some(value)),
        Err(keyring::Error::NoEntry) => Ok(None),
        Err(e) => Err(e.to_string()),
    }
}

#[tauri::command]
pub async fn delete_credential(key: String) -> Result<(), String> {
    let entry = Entry::new(SERVICE_NAME, &key).map_err(|e| e.to_string())?;
    match entry.delete_credential() {
        Ok(()) => Ok(()),
        Err(keyring::Error::NoEntry) => Ok(()),
        Err(e) => Err(e.to_string()),
    }
}

#[cfg(all(test, target_os = "windows"))]
mod tests {
    use super::*;
    #[tokio::test]
    async fn credentials_survive_a_new_entry_and_are_removed() {
        let key = format!("test-credential-{}", std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_nanos());
        store_credential(key.clone(), "disposable-test-value".to_string()).await.unwrap();
        let loaded = load_credential(key.clone()).await;
        // Always clean up our disposable credential, including on assertion failure.
        delete_credential(key.clone()).await.unwrap();
        assert_eq!(loaded.unwrap().as_deref(), Some("disposable-test-value"));
        assert_eq!(load_credential(key).await.unwrap(), None);
    }
}
