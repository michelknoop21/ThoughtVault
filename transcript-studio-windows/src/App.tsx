import { BrowserRouter, Routes, Route, Navigate, useNavigate } from "react-router-dom";
import { useEffect, useRef, useState } from "react";
import { listen } from "@tauri-apps/api/event";
import { TitleBar } from "./components/layout/TitleBar";
import { Sidebar } from "./components/layout/Sidebar";
import { CallAlertOverlay } from "./components/calendar/CallAlertOverlay";
import { YingaFooter } from "./components/brand/YingaFooter";
import { ErrorBoundary } from "./components/ui/ErrorBoundary";
import { InfoBarHost } from "./components/ui/InfoBar";
import { LoginPage } from "./pages/LoginPage";
import { HomePage } from "./pages/HomePage";
import { RecordingPage } from "./pages/RecordingPage";
import { TranscriptsPage } from "./pages/TranscriptsPage";
import { ProfilesPage } from "./pages/ProfilesPage";
import { AccountPage } from "./pages/AccountPage";
import { SettingsPage } from "./pages/SettingsPage";
import { AdminPage } from "./pages/AdminPage";
import FeedbackWidget from "./components/FeedbackWidget";
import { OnboardingWizard } from "./components/onboarding/OnboardingWizard";
import { useAuthStore } from "./stores/authStore";
import { useSettingsStore } from "./stores/settingsStore";
import { useProfilesStore } from "./stores/profilesStore";
import { MicrosoftGraphService } from "./services/microsoftGraph";
import { api } from "./services/api";
import { initCrashReporter } from "./services/crashReporter";
import type { Profile } from "./types";

// Initialize crash reporter immediately
initCrashReporter();

function OfflineQueueBanner() {
  const [count, setCount] = useState(0);
  const [processing, setProcessing] = useState(false);
  const isProcessingRef = useRef(false);

  useEffect(() => {
    let cancelled = false;

    async function checkAndProcess() {
      try {
        const { getQueue, processQueue } = await import("./services/offlineQueue");
        const queue = await getQueue();
        if (cancelled) return;
        setCount(queue.length);

        // Try to process queued uploads if there are any and we're not already processing
        if (queue.length > 0 && !isProcessingRef.current) {
          isProcessingRef.current = true;
          setProcessing(true);
          try {
            await processQueue();
            // Re-check queue after processing
            const remaining = await getQueue();
            if (!cancelled) setCount(remaining.length);
          } catch {
            // Processing failed — will retry on next interval
          }
          isProcessingRef.current = false;
          if (!cancelled) setProcessing(false);
        }
      } catch {
        // Queue not available
      }
    }
    checkAndProcess();
    const interval = setInterval(checkAndProcess, 10000);
    return () => { cancelled = true; clearInterval(interval); };
  }, []);

  if (count === 0) return null;

  return (
    <div style={{
      padding: "6px 14px",
      background: "var(--fill-accent-default)",
      color: "#fff",
      fontSize: 12,
      fontWeight: 500,
      display: "flex",
      alignItems: "center",
      gap: 8,
      flexShrink: 0,
    }}>
      <span style={{ width: 8, height: 8, borderRadius: "50%", background: "#fff", opacity: 0.7, animation: "widget-pulse 1.5s ease-in-out infinite" }} />
      <span style={{ flex: 1 }}>
        {processing
          ? `${count} opname${count !== 1 ? "s" : ""} worden verstuurd...`
          : `${count} opname${count !== 1 ? "s" : ""} in wachtrij — wordt automatisch verstuurd`
        }
      </span>
    </div>
  );
}

function AppShell({ children }: { children: React.ReactNode }) {
  return (
    <>
      <div className="app-shell">
        <TitleBar />
        <div style={{ flex: 1, display: "flex", minHeight: 0 }}>
          <Sidebar />
          <main className="app-main">
            <OfflineQueueBanner />
            <div className="app-main-content">
              {children}
            </div>
            <YingaFooter compact />
          </main>
        </div>
      </div>
      <FeedbackWidget />
      <CallAlertOverlay />
    </>
  );
}

function KeyboardShortcuts() {
  const navigate = useNavigate();

  useEffect(() => {
    function handleKeyDown(e: KeyboardEvent) {
      // Ignore if user is typing in an input/textarea/contenteditable
      const target = e.target as HTMLElement;
      if (
        target.tagName === "INPUT" ||
        target.tagName === "TEXTAREA" ||
        target.isContentEditable
      ) {
        return;
      }

      const ctrl = e.ctrlKey || e.metaKey;

      // Ctrl+1..5 = Navigate tabs
      if (ctrl && e.key === "1") { e.preventDefault(); navigate("/"); }
      if (ctrl && e.key === "2") { e.preventDefault(); navigate("/recording"); }
      if (ctrl && e.key === "3") { e.preventDefault(); navigate("/transcripts"); }
      if (ctrl && e.key === "4") { e.preventDefault(); navigate("/settings"); }
      if (ctrl && e.key === "5") { e.preventDefault(); navigate("/profiles"); }

      // Ctrl+N = New recording
      if (ctrl && e.key === "n") { e.preventDefault(); navigate("/recording"); }

      // Ctrl+F = Focus search in transcripts
      if (ctrl && e.key === "f") { e.preventDefault(); navigate("/transcripts"); }

      // Escape = Close modals (handled by individual components)

      // Ctrl+R = Go to recording page
      if (ctrl && e.key === "r") { e.preventDefault(); navigate("/recording"); }
    }

    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [navigate]);

  return null;
}

function ProtectedRoutes() {
  const { isAuthenticated } = useAuthStore();
  const { has_completed_onboarding, updateSettings } = useSettingsStore();
  const setProfiles = useProfilesStore((s) => s.setProfiles);

  // Load profiles and OAuth config from API on auth
  useEffect(() => {
    if (isAuthenticated) {
      api.getProfiles().then((profiles: Profile[]) => {
        if (profiles.length > 0) {
          setProfiles(profiles);
        }
      });
      api.getMySettings().then((settings) => {
        updateSettings({
          ms365_client_id: settings.ms365_client_id || undefined,
          ms365_tenant_id: settings.ms365_tenant_id || undefined,
        });
      }).catch(() => { /* ignore - settings will remain as-is */ });
    }
  }, [isAuthenticated, setProfiles, updateSettings]);

  if (!isAuthenticated) {
    return <Navigate to="/login" replace />;
  }

  if (!has_completed_onboarding) {
    return (
      <div className="app-shell">
        <OnboardingWizard />
      </div>
    );
  }

  return (
    <AppShell>
      <KeyboardShortcuts />
      <Routes>
        <Route path="/"            element={<HomePage />} />
        <Route path="/recording"   element={<RecordingPage />} />
        <Route path="/transcripts" element={<TranscriptsPage />} />
        <Route path="/profiles"    element={<ProfilesPage />} />
        <Route path="/account"     element={<AccountPage />} />
        <Route path="/settings"    element={<SettingsPage />} />
        <Route path="/admin"       element={<AdminPage />} />
        <Route path="*"            element={<Navigate to="/" replace />} />
      </Routes>
    </AppShell>
  );
}

function UpdateRequiredOverlay({ currentVersion, minimumVersion }: { currentVersion: string; minimumVersion: string }) {
  const serverUrl = useSettingsStore((s) => s.server_url);
  return (
    <div style={{
      position: "fixed", inset: 0, zIndex: 9999,
      background: "var(--surface-primary)", display: "grid", placeItems: "center",
    }}>
      <div style={{ textAlign: "center", maxWidth: 400, padding: 32 }}>
        <div style={{ marginBottom: 20 }}>
          <svg width="48" height="48" viewBox="0 0 24 24" fill="none" style={{ margin: "0 auto 16px" }}>
            <path d="M12 2L2 7l10 5 10-5-10-5zM2 17l10 5 10-5M2 12l10 5 10-5" stroke="var(--text-accent)" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round"/>
          </svg>
          <p style={{ font: "var(--type-subtitle)", color: "var(--text-primary)", marginBottom: 8 }}>Update vereist</p>
          <p style={{ font: "var(--type-body)", color: "var(--text-secondary)" }}>
            Je huidige versie ({currentVersion}) wordt niet meer ondersteund.
            Download versie {minimumVersion} of nieuwer om door te gaan.
          </p>
        </div>
        <a
          href={`${serverUrl.replace(/\/api\/?$/, "")}/download`}
          target="_blank"
          rel="noopener noreferrer"
          className="btn btn-accent"
          style={{ display: "inline-flex", padding: "10px 24px", textDecoration: "none" }}
        >
          Download update
        </a>
      </div>
    </div>
  );
}

export default function App() {
  const [updateRequired, setUpdateRequired] = useState<{ current: string; minimum: string } | null>(null);

  // Force update check on launch (skip in browser dev mode)
  useEffect(() => {
    if (!("__TAURI_INTERNALS__" in window)) return;
    (async () => {
      try {
        const { getAppVersion } = await import("./services/tauriCommands");
        const currentVersion = await getAppVersion();
        const versionInfo = await api.checkVersion();
        if (!versionInfo) return;

        // Compare semver: check if current < minimum
        const parse = (v: string) => v.split(".").map(Number);
        const cur = parse(currentVersion);
        const min = parse(versionInfo.minimum_version);
        const isOutdated = cur[0] < min[0] || (cur[0] === min[0] && cur[1] < min[1]) || (cur[0] === min[0] && cur[1] === min[1] && cur[2] < min[2]);

        if (isOutdated) {
          setUpdateRequired({ current: currentVersion, minimum: versionInfo.minimum_version });
        }
      } catch {
        // Version check failed — allow app to continue
      }
    })();
  }, []);

  // Detect system theme preference
  useEffect(() => {
    const mq = window.matchMedia("(prefers-color-scheme: dark)");
    document.documentElement.dataset.theme = mq.matches ? "dark" : "light";
    const handler = (e: MediaQueryListEvent) => {
      document.documentElement.dataset.theme = e.matches ? "dark" : "light";
    };
    mq.addEventListener("change", handler);
    return () => mq.removeEventListener("change", handler);
  }, []);

  // Handle Microsoft 365 OAuth deep-link callbacks
  useEffect(() => {
    const unlisten = listen<string>("oauth-callback", async (event) => {
      try {
        await MicrosoftGraphService.handleAuthCallback(event.payload);
      } catch (err) {
        console.error("[OAuth] Callback error:", err);
      }
    });
    return () => { unlisten.then((fn) => fn()); };
  }, []);

  if (updateRequired) {
    return <UpdateRequiredOverlay currentVersion={updateRequired.current} minimumVersion={updateRequired.minimum} />;
  }

  return (
    <ErrorBoundary>
      <BrowserRouter>
        <div style={{ height: "100%" }}>
          <Routes>
            <Route path="/login" element={<LoginPage />} />
            <Route path="/*"     element={<ProtectedRoutes />} />
          </Routes>
          <InfoBarHost />
        </div>
      </BrowserRouter>
    </ErrorBoundary>
  );
}
