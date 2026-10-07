import { useUpdateCheck } from "./hooks/useUpdateCheck";
import { UpdateBanner } from "./components/ui/UpdateBanner";
import { listen } from "@tauri-apps/api/event";
import { MicrosoftGraphService } from "./services/microsoftGraph";
import { BrowserRouter, Routes, Route, Navigate, useNavigate, useLocation } from "react-router-dom";
import { useEffect, useState } from "react";
import { TitleBar } from "./components/layout/TitleBar";
import { Sidebar } from "./components/layout/Sidebar";
import { CallAlertOverlay } from "./components/calendar/CallAlertOverlay";
import { BrandFooter } from "./components/brand/BrandFooter";
import { ErrorBoundary } from "./components/ui/ErrorBoundary";
import { InfoBarHost } from "./components/ui/InfoBar";
import { HomePage } from "./pages/HomePage";
import { RecordingPage } from "./pages/RecordingPage";
import { TranscriptsPage } from "./pages/TranscriptsPage";
import { ProfilesPage } from "./pages/ProfilesPage";
import { SettingsPage } from "./pages/SettingsPage";
import { TasksPage } from "./pages/TasksPage";
import { PeoplePage } from "./pages/PeoplePage";
import { ProcessingBar } from "./components/ProcessingBar";
import { OnboardingWizard } from "./components/onboarding/OnboardingWizard";
import { useSettingsStore } from "./stores/settingsStore";
import { useProfilesStore } from "./stores/profilesStore";
import { useLocalTranscriptsStore } from "./stores/localTranscriptsStore";
import { initCrashReporter } from "./services/crashReporter";
import { useGlobalRecordingHandler } from "./hooks/useGlobalRecordingHandler";
import { useAICommands } from "./hooks/useAICommands";
import { canOpenRoute, shouldBlockForLocalNotes } from "./services/routeAccess";


initCrashReporter();

function AppShell({ children }: { children: React.ReactNode }) {
  const { update } = useUpdateCheck();
  const dismissed = useSettingsStore((s) => s.dismissed_update_version);
  return (
    <>
      <div className="app-shell">
        <a href="#main-content" className="skip-link">Ga naar hoofdinhoud</a>
        <TitleBar />
        <div style={{ flex: 1, display: "flex", minHeight: 0 }}>
          <Sidebar />
          <main className="app-main" id="main-content">
            <ProcessingBar />
            {update && dismissed !== update.version && <UpdateBanner update={update} onDismiss={() => void useSettingsStore.getState().updateSettings({ dismissed_update_version: update.version })} />}
            <div className="app-main-content">
              {children}
            </div>
            <BrandFooter compact />
          </main>
        </div>
      </div>
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
      if (ctrl && e.key === "6") { e.preventDefault(); navigate("/people"); }

      // Ctrl+N = New recording
      if (ctrl && e.key === "n") { e.preventDefault(); navigate("/recording"); }

      // Ctrl+F = Focus search in transcripts
      if (ctrl && e.key === "f") { e.preventDefault(); navigate("/transcripts"); }

      // Escape = Close modals (handled by individual components)

      // Don't intercept Ctrl+R — let the webview handle refresh
    }

    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [navigate]);

  return null;
}

function ProtectedRoutes() {
  const { has_completed_onboarding } = useSettingsStore();
  const location = useLocation();
  const showLocalProfiles = useProfilesStore((state) => state.showLocalProfiles);
  useEffect(() => { showLocalProfiles(); }, [showLocalProfiles]);
  useGlobalRecordingHandler();
  useAICommands();

  if (!canOpenRoute(location.pathname, "local", false)) return <Navigate to="/" replace />;
  if (!has_completed_onboarding) return <div className="app-shell"><OnboardingWizard /></div>;

  return (
    <AppShell>
      <KeyboardShortcuts />
      <Routes>
        <Route path="/" element={<HomePage />} />
        <Route path="/recording" element={<RecordingPage />} />
        <Route path="/tasks" element={<TasksPage />} />
        <Route path="/transcripts" element={<TranscriptsPage />} />
        <Route path="/profiles" element={<ProfilesPage />} />
        <Route path="/people" element={<PeoplePage />} />
        <Route path="/settings" element={<SettingsPage />} />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </AppShell>
  );
}

export default function App() {
  const processingMode = useSettingsStore((s) => s.processing_mode);
  const [localReady, setLocalReady] = useState(false);
  const [localLoadError, setLocalLoadError] = useState<string | null>(null);

  async function loadLocalNotes() {
    try {
      await useLocalTranscriptsStore.getState().hydrate();
      setLocalReady(true);
      setLocalLoadError(null);
    } catch (error) {
      setLocalLoadError(error instanceof Error ? error.message : "Lokale notulen laden mislukt");
    }
  }

  useEffect(() => { void loadLocalNotes(); }, []);

  // One-time migration of recordings from %APPDATA% (Roaming) to %LOCALAPPDATA% (Local).
  // Roaming was getting picked up by OneDrive Known Folder Move and roaming profiles,
  // which locked WAV files mid-upload and caused "field required" 422s on the server.
  useEffect(() => {
    if (!("__TAURI_INTERNALS__" in window)) return;
    (async () => {
      try {
        const { migrateRecordingsDir } = await import("./services/tauriCommands");
        const moved = await migrateRecordingsDir();
        if (moved > 0) {
          console.log(`[App] Migrated ${moved} recording(s) to %LOCALAPPDATA%`);
        }
      } catch (err) {
        console.warn("[App] Recording-dir migration failed:", err);
      }
    })();
  }, []);

  useEffect(() => {
    if (!("__TAURI_INTERNALS__" in window)) return;
    const unlisten = listen<string>("oauth-callback", async (event) => {
      try {
        let url = event.payload;
        try { const parsed = JSON.parse(url); if (Array.isArray(parsed)) url = parsed[0]; } catch { /* URL payload */ }
        if (url?.startsWith("transcript-studio://auth/callback")) await MicrosoftGraphService.handleAuthCallback(url);
      } catch (error) { console.error("Agenda aanmelden mislukt", error); }
    });
    return () => { void unlisten.then((stop) => stop()); };
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

  if (shouldBlockForLocalNotes(processingMode, localReady)) {
    return localLoadError ? (
      <div className="empty-state">
        <p>Lokale notulen konden niet worden geladen: {localLoadError}</p>
        <button className="btn btn-accent" onClick={() => void loadLocalNotes()}>Opnieuw proberen</button>
      </div>
    ) : null;
  }

  return (
    <ErrorBoundary>
      <BrowserRouter>
        <div style={{ height: "100%" }}>
          <Routes>
            <Route path="/login" element={<Navigate to="/" replace />} />
            <Route path="/*"     element={<ProtectedRoutes />} />
          </Routes>
          <InfoBarHost />
        </div>
      </BrowserRouter>
    </ErrorBoundary>
  );
}
