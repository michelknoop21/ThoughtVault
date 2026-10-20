use keyring::Entry;

const SERVICE_NAME: &str = "nl.prezent.transcript-studio";

fn storage_error(error: keyring::Error) -> String {
    // Do not format arbitrary credential attributes or blobs into UI errors.
    match error {
        keyring::Error::TooLong(_, _) => "Sleutel te lang voor Windows Credential Manager. Controleer of je alleen de API-sleutel hebt geplakt.".into(),
        keyring::Error::NoStorageAccess(_) => "Windows Credential Manager is niet toegankelijk voor deze gebruiker.".into(),
        keyring::Error::PlatformFailure(error) => format!("Windows Credential Manager: {error}"),
        _ => "Windows Credential Manager kon de sleutel niet opslaan.".into(),
    }
}

#[tauri::command]
pub async fn store_credential(key: String, value: String) -> Result<(), String> {
    let entry = Entry::new(SERVICE_NAME, &key).map_err(storage_error)?;
    entry.set_password(&value).map_err(storage_error)
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
    #[test]
    fn storage_errors_do_not_expose_credential_values() {
        let secret = "QA-secret-must-not-appear";
        assert!(!storage_error(keyring::Error::Invalid("password".into(), secret.into())).contains(secret));
        assert!(storage_error(keyring::Error::TooLong(secret.into(), 2560)).contains("te lang"));
    }

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
