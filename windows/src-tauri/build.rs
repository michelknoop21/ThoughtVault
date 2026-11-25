fn main() {
    println!("cargo:rerun-if-changed=icons");
    println!("cargo:rerun-if-changed=tauri.conf.json");
    println!("cargo:rerun-if-env-changed=TAURI_CONFIG");
    // `ThoughtVault.exe --mcp` runs without Tauri, so it needs the identifier at compile time.
    // The CLI passes `--config` overrides (the Dev channel identifier) to build scripts as TAURI_CONFIG.
    let base: serde_json::Value = serde_json::from_str(&std::fs::read_to_string("tauri.conf.json").unwrap()).unwrap();
    let mut identifier = base["identifier"].as_str().unwrap().to_string();
    if let Ok(raw) = std::env::var("TAURI_CONFIG") {
        let parsed = serde_json::from_str::<serde_json::Value>(&raw)
            .ok()
            .or_else(|| std::fs::read_to_string(&raw).ok().and_then(|text| serde_json::from_str(&text).ok()));
        if let Some(id) = parsed.as_ref().and_then(|config| config["identifier"].as_str()) {
            identifier = id.to_string();
        }
    }
    println!("cargo:rustc-env=TV_APP_IDENTIFIER={identifier}");
    tauri_build::build()
}
