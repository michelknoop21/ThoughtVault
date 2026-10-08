use keyring::Entry;

const SERVICE_NAME: &str = "nl.prezent.transcript-studio";

#[tauri::command]
pub async fn store_credential(key: String, value: String) -> Result<(), String> {
    let entry = Entry::new(SERVICE_NAME, &key).map_err(|e| e.to_string())?;
    entry.set_password(&value).map_err(|e| e.to_string())
}

#[cfg(all(test, target_os = "windows"))]
mod tests {
    use super::*;

    #[tokio::test]
    async fn credentials_survive_new_entries() {
        let key = format!("installer-test-{}", std::process::id());
        store_credential(key.clone(), "test-value".into()).await.unwrap();
        let value = load_credential(key.clone()).await;
        delete_credential(key.clone()).await.unwrap();
        assert_eq!(value.unwrap().as_deref(), Some("test-value"));
        assert_eq!(load_credential(key).await.unwrap(), None);
    }
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
