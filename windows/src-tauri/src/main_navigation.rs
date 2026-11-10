use std::sync::atomic::{AtomicBool, Ordering};
use tauri::utils::config::{BuildConfig, FrontendDist, WebviewUrl, WindowConfig};

pub(crate) fn packaged_main_url(
    window: &WindowConfig,
    build: &BuildConfig,
) -> Result<String, &'static str> {
    if matches!(build.frontend_dist, Some(FrontendDist::Url(_))) {
        return Err("main requires packaged frontend assets");
    }
    let WebviewUrl::App(path) = &window.url else {
        return Err("main requires a packaged app URL");
    };
    // Match Tauri 2's packaged-protocol mapping; window config retains scheme/path ownership.
    let base = if cfg!(windows) || cfg!(target_os = "android") {
        if window.use_https_scheme {
            "https://tauri.localhost/"
        } else {
            "http://tauri.localhost/"
        }
    } else {
        "tauri://localhost"
    };
    let base = tauri::Url::parse(base).map_err(|_| "invalid packaged app base")?;
    let expected = if path.to_str() == Some("index.html") {
        base.clone()
    } else {
        base.join(&path.to_string_lossy())
            .map_err(|_| "invalid packaged app path")?
    };
    if expected.scheme() != base.scheme()
        || expected.host_str() != base.host_str()
        || expected.port() != base.port()
        || !expected.username().is_empty()
        || expected.password().is_some()
    {
        return Err("main app path must stay on the packaged origin");
    }
    Ok(expected.into())
}

pub(crate) struct MainNavigation {
    expected: String,
    started: AtomicBool,
}

impl MainNavigation {
    pub(crate) fn new(expected: String) -> Self {
        Self {
            expected,
            started: AtomicBool::new(false),
        }
    }

    pub(crate) fn allows(&self, label: &str, url: &str, debug: bool) -> bool {
        if debug || label != "main" {
            return true;
        }
        // shortcut: one bundled initial navigation, revisit if startup ever needs redirects.
        url == self.expected && !self.started.swap(true, Ordering::SeqCst)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn permits_only_the_trusted_first_main_document() {
        let guard = MainNavigation::new("http://tauri.localhost/".into());
        assert!(!guard.allows("main", "https://external.example/", false));
        assert!(!guard.allows("main", "http://tauri.localhost/other", false));
        assert!(guard.allows(
            "recording-widget",
            "http://tauri.localhost/widget.html",
            false
        ));
        assert!(guard.allows("main", "http://tauri.localhost/", false));
        assert!(!guard.allows("main", "http://tauri.localhost/", false));
        assert!(!guard.allows("main", "http://tauri.localhost/redirect", false));
        assert!(!guard.allows("main", "https://external.example/", false));
    }

    #[test]
    fn debug_retains_reload() {
        let guard = MainNavigation::new("http://tauri.localhost/".into());
        assert!(guard.allows("main", "http://localhost:1420/", true));
        assert!(guard.allows("main", "http://localhost:1420/", true));
    }

    #[test]
    fn resolves_configured_packaged_path_and_scheme() {
        let mut window = WindowConfig::default();
        let build = BuildConfig::default();
        let default = packaged_main_url(&window, &build).unwrap();
        assert_eq!(
            default,
            if cfg!(windows) || cfg!(target_os = "android") {
                "http://tauri.localhost/"
            } else {
                "tauri://localhost"
            }
        );
        window.use_https_scheme = true;
        window.url = WebviewUrl::App("main.html".into());
        assert_eq!(
            packaged_main_url(&window, &build).unwrap(),
            if cfg!(windows) || cfg!(target_os = "android") {
                "https://tauri.localhost/main.html"
            } else {
                "tauri://localhost/main.html"
            }
        );
        window.url = WebviewUrl::App("//external.example/".into());
        assert!(packaged_main_url(&window, &build).is_err());
        window.url = WebviewUrl::External(tauri::Url::parse("https://external.example/").unwrap());
        assert!(packaged_main_url(&window, &build).is_err());
        window.url = WebviewUrl::App("index.html".into());
        let mut remote = BuildConfig::default();
        remote.frontend_dist = Some(FrontendDist::Url(
            tauri::Url::parse("https://external.example/").unwrap(),
        ));
        assert!(packaged_main_url(&window, &remote).is_err());
    }
}
