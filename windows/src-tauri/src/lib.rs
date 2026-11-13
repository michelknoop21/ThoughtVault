#[macro_use]
mod applog;
mod audio;
mod commands;
mod transcribe;
mod personal_corrections;
mod main_navigation;

use commands::audio::SharedRecordingState;
use std::sync::{Arc, Mutex};
use tauri::{Emitter, Listener, Manager};

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let recording_state: SharedRecordingState = Arc::new(Mutex::new(Default::default()));

    tauri::Builder::default()
        .manage(recording_state)
        .on_window_event(|window, event| {
            if window.label() == "main" {
                if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                    // Keep main through webview reload; JS explicitly destroys only after idle checks.
                    api.prevent_close();
                    let _ = window.hide();
                }
            }
        })
        .manage(transcribe::ModelDownloadControl::default())
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_updater::Builder::new().build())
        .plugin(tauri_plugin_notification::init())
        .plugin(tauri_plugin_store::Builder::default().build())
        .plugin(tauri_plugin_single_instance::init(|app, _args, _cwd| {
            if let Some(window) = app.get_webview_window("main") {
                let _ = window.show();
                let _ = window.unminimize();
                let _ = window.set_focus();
            }
        }))
        .plugin(tauri_plugin_deep_link::init())
        .plugin(tauri_plugin_fs::init())
        .plugin(tauri_plugin_dialog::init())
        .setup(|app| {
            applog::init(app.path().app_data_dir()?.join("logs"));
            let default = std::panic::take_hook();
            std::panic::set_hook(Box::new(move |info| {
                // Panic payloads may contain transcript text; persist only the source location.
                let location = info.location().map(|l| l.to_string()).unwrap_or_default();
                applog::write("error", "panic", &format!("panic at {location}"));
                default(info);
            }));
            let main_config = app.config().app.windows.iter()
                .find(|window| window.label == "main")
                .ok_or("main window configuration missing")?;
            let expected = main_navigation::packaged_main_url(main_config, &app.config().build)?;
            let navigation = main_navigation::MainNavigation::new(expected);
            let main_window = tauri::WebviewWindowBuilder::from_config(app, main_config)?
                .on_navigation(move |url| navigation.allows("main", url.as_str(), cfg!(debug_assertions)))
                .build()?;

            // Apply Windows 11 Mica effect to main window
            #[cfg(target_os = "windows")]
            {
                use window_vibrancy::apply_mica;
                if let Err(e) = apply_mica(&main_window, Some(true)) {
                    elog!("[Window] Mica effect niet beschikbaar: {}", e);
                }
            }

            // No vibrancy effect on the recording-widget — it uses CSS background
            // with transparent: true on the window, so acrylic would fill the
            // entire rectangular window behind the pill shape.

            // Handle deep-link OAuth callbacks (Microsoft 365)
            let app_handle2 = app.handle().clone();
            app.listen("deep-link://new-url", move |event| {
                let payload = event.payload().to_string();
                elog!("[DeepLink] OAuth callback ontvangen");

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
            applog::log_write,
            applog::log_tail,
            applog::log_reveal,
            applog::log_scrub,
            applog::session_begin,
            applog::session_stage,
            // Audio
            commands::audio::get_audio_devices,
            commands::audio::recording_active,
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
            commands::filesystem::import_audio,
            commands::filesystem::audio_duration,
            commands::filesystem::migrate_recordings_dir,
            commands::filesystem::concatenate_wav_files,
            // HTTP
            commands::http::proxy_request,
            commands::http::proxy_upload,
            commands::http::http_sse_stream,
            commands::http::obsidian_put,
            commands::http::obsidian_get,
            commands::http::obsidian_test,
            // System
            commands::system::get_network_status,
            commands::system::detect_meeting_apps,
            commands::system::get_app_version,
            commands::system::get_system_specs,
            commands::system::open_microphone_settings,
            commands::system::download_and_run_installer,
            // Local transcription (whisper.cpp)
            transcribe::whisper_model_status,
            transcribe::download_whisper_model,
            transcribe::cancel_whisper_download,
            transcribe::whisper_download_status,
            transcribe::remove_whisper_model,
            transcribe::show_whisper_model,
            transcribe::transcribe_local,
            personal_corrections::load_personal_corrections,
            personal_corrections::save_personal_corrections,
            personal_corrections::read_context_file,
            personal_corrections::write_context_file,
            personal_corrections::set_aside_context_file,
        ])
        .build(tauri::generate_context!())
        .expect("error while building tauri application")
        .run(|_app, event| {
            if let tauri::RunEvent::Exit = event {
                applog::session_end();
            }
        });
}
