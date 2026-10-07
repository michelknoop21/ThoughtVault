use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NetworkStatus {
    pub is_online: bool,
    pub connection_type: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MeetingApp {
    pub name: String,
    pub process_name: String,
    pub is_running: bool,
}

#[tauri::command]
pub async fn get_network_status() -> Result<NetworkStatus, String> {
    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(3))
        .build()
        .map_err(|e| e.to_string())?;

    let is_online = client
        .head("https://connectivitycheck.gstatic.com/generate_204")
        .send()
        .await
        .map(|r| r.status().as_u16() == 204)
        .unwrap_or(false);

    Ok(NetworkStatus {
        is_online,
        connection_type: if is_online { "internet".to_string() } else { "none".to_string() },
    })
}

#[tauri::command]
pub async fn detect_meeting_apps() -> Result<Vec<MeetingApp>, String> {
    let candidates = vec![
        ("Microsoft Teams", "ms-teams", "ms-teams.exe"),
        ("Microsoft Teams (Legacy)", "teams-legacy", "Teams.exe"),
        ("Zoom", "zoom", "Zoom.exe"),
        ("Google Chrome (Meet)", "chrome", "chrome.exe"),
        ("Cisco Webex", "webex", "WebexHost.exe"),
        ("GoTo Meeting", "goto", "g2mstart.exe"),
        ("Whereby", "whereby", "whereby.exe"),
    ];

    let mut result = Vec::new();

    #[cfg(target_os = "windows")]
    {
        use std::os::windows::process::CommandExt;
        const CREATE_NO_WINDOW: u32 = 0x08000000;

        let output = std::process::Command::new("tasklist")
            .args(["/fo", "csv", "/nh"])
            .creation_flags(CREATE_NO_WINDOW)
            .output()
            .map_err(|e| format!("tasklist mislukt: {}", e))?;

        let tasklist = String::from_utf8_lossy(&output.stdout).to_lowercase();

        for (name, id, process) in &candidates {
            let is_running = tasklist.contains(&process.to_lowercase());
            result.push(MeetingApp {
                name: name.to_string(),
                process_name: id.to_string(),
                is_running,
            });
        }
    }

    #[cfg(not(target_os = "windows"))]
    {
        for (name, id, _) in &candidates {
            result.push(MeetingApp {
                name: name.to_string(),
                process_name: id.to_string(),
                is_running: false,
            });
        }
    }

    Ok(result)
}

#[tauri::command]
pub async fn get_app_version() -> Result<String, String> {
    Ok(env!("CARGO_PKG_VERSION").to_string())
}

/// Download an installer (MSI) to the temp dir, launch it, then quit the app so
/// the installer can replace the running binary. Pragmatic in-app update — the
/// MSI is already developer-signed on the server, no local signature check.
#[tauri::command]
pub async fn download_and_run_installer(
    app: tauri::AppHandle,
    url: String,
) -> Result<(), String> {
    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(600))
        .build()
        .map_err(|e| e.to_string())?;

    let resp = client.get(&url).send().await.map_err(|e| e.to_string())?;
    if !resp.status().is_success() {
        return Err(format!("Download mislukt: HTTP {}", resp.status()));
    }
    let bytes = resp.bytes().await.map_err(|e| e.to_string())?;

    let filename = url
        .rsplit('/')
        .next()
        .filter(|s| !s.is_empty())
        .unwrap_or("ThoughtVault-update.msi");
    let dest = std::env::temp_dir().join(filename);
    tokio::fs::write(&dest, &bytes)
        .await
        .map_err(|e| format!("Kan installer niet opslaan: {}", e))?;

    #[cfg(target_os = "windows")]
    {
        // Launch the MSI via msiexec and quit — the installer takes over.
        std::process::Command::new("msiexec")
            .arg("/i")
            .arg(&dest)
            .spawn()
            .map_err(|e| format!("Kan installer niet starten: {}", e))?;
        app.exit(0);
    }

    #[cfg(not(target_os = "windows"))]
    {
        let _ = &app; // suppress unused warning off-Windows
        return Err("Installer starten wordt alleen op Windows ondersteund".to_string());
    }

    #[allow(unreachable_code)]
    Ok(())
}
