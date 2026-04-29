mod audio;
mod commands;

use commands::audio::SharedRecordingState;
use std::sync::{Arc, Mutex};
use tauri::{Emitter, Listener, Manager};

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let recording_state: SharedRecordingState = Arc::new(Mutex::new(Default::default()));

    tauri::Builder::default()
        .manage(recording_state)
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_notification::init())
        .plugin(tauri_plugin_store::Builder::default().build())
        .plugin(tauri_plugin_single_instance::init(|_app, _args, _cwd| {}))
        .plugin(tauri_plugin_deep_link::init())
        .plugin(tauri_plugin_fs::init())
        .setup(|app| {
            let main_window = app.get_webview_window("main").unwrap();

            // Apply Windows 11 Mica effect to main window
            #[cfg(target_os = "windows")]
            {
                use window_vibrancy::apply_mica;
                if let Err(e) = apply_mica(&main_window, Some(true)) {
                    eprintln!("[Window] Mica effect niet beschikbaar: {}", e);
                }
            }

            // No vibrancy effect on the recording-widget — it uses CSS background
            // with transparent: true on the window, so acrylic would fill the
            // entire rectangular window behind the pill shape.

            // Handle deep-link OAuth callbacks (Microsoft 365)
            let app_handle2 = app.handle().clone();
            app.listen("deep-link://new-url", move |event| {
                let payload = event.payload().to_string();
                eprintln!("[DeepLink] OAuth callback: {}", payload);

                if let Some(window) = app_handle2.get_webview_window("main") {
                    let _ = window.emit("oauth-callback", payload);
                    let _ = window.show();
                    let _ = window.set_focus();
                }
            });

            // Open DevTools in debug builds
            #[cfg(debug_assertions)]
            main_window.open_devtools();

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            // Audio
            commands::audio::get_audio_devices,
            commands::audio::start_recording,
            commands::audio::stop_recording,
            commands::audio::pause_recording,
            commands::audio::resume_recording,
            // Auth / credentials
            commands::auth::store_credential,
            commands::auth::load_credential,
            commands::auth::delete_credential,
            // Filesystem
            commands::filesystem::list_recordings,
            commands::filesystem::delete_recording,
            commands::filesystem::cleanup_old_recordings,
            commands::filesystem::get_recordings_dir,
            commands::filesystem::migrate_recordings_dir,
            commands::filesystem::concatenate_wav_files,
            // HTTP
            commands::http::proxy_request,
            commands::http::proxy_upload,
            commands::http::http_sse_stream,
            // System
            commands::system::get_network_status,
            commands::system::detect_meeting_apps,
            commands::system::get_app_version,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
