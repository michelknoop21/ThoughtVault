import { BrowserRouter, Routes, Route, Navigate, useNavigate, useLocation } from "react-router-dom";
import { createContext, useContext, useEffect, useRef, useState } from "react";
import { listen } from "@tauri-apps/api/event";
import { startSupportOwner } from "./services/supportOwner";
import { useUpdateCheck } from "./hooks/useUpdateCheck";
import { UpdateBanner } from "./components/ui/UpdateBanner";
import { TitleBar } from "./components/layout/TitleBar";
import { Sidebar } from "./components/layout/Sidebar";
import { CallAlertOverlay } from "./components/calendar/CallAlertOverlay";
import { ErrorBoundary } from "./components/ui/ErrorBoundary";
import { InfoBarHost } from "./components/ui/InfoBar";
import { LoginPage } from "./pages/LoginPage";
import { HomePage } from "./pages/HomePage";
import { RecordingPage } from "./pages/RecordingPage";
import { TranscriptsPage } from "./pages/TranscriptsPage";
import { AccountPage } from "./pages/AccountPage";
import { SettingsPage } from "./pages/SettingsPage";
import { AdminPage } from "./pages/AdminPage";
import { TasksPage } from "./pages/TasksPage";
import { PeoplePage } from "./pages/PeoplePage";
import { ProcessingBar } from "./components/ProcessingBar";
import { OfflineQueueBanner } from "./components/OfflineQueueBanner";
import { IdentityGate } from "./components/support/IdentityGate";
import { isValidEmail, useSupportStore } from "./stores/supportStore";
import { OnboardingWizard } from "./components/onboarding/OnboardingWizard";
import { useAuthStore } from "./stores/authStore";
import { useSettingsStore } from "./stores/settingsStore";
import { currentProfileChoices, useProfilesStore } from "./stores/profilesStore";
import { useRecordingStore } from "./stores/recordingStore";
import { useTranscriptsStore } from "./stores/transcriptsStore";
import { useLocalTranscriptsStore } from "./stores/localTranscriptsStore";
import { MicrosoftGraphService } from "./services/microsoftGraph";
import { api } from "./services/api";
import { createSSEClient } from "./services/sse";
import { initCrashReporter } from "./services/crashReporter";
import { installClickPath, installConsoleForwarding, logRoute } from "./services/appLog";
import { initMeetingNotifications } from "./services/meetingNotifications";
import { useGlobalRecordingHandler } from "./hooks/useGlobalRecordingHandler";
import { useSupportLifecycle } from "./hooks/useSupportLifecycle";
import { useToast } from "./components/ui/InfoBar";
import type { Profile } from "./types";
import { canOpenRoute, shouldBlockForLocalNotes } from "./services/routeAccess";

initCrashReporter(); installConsoleForwarding(); installClickPath();

const UpdateContext = createContext<ReturnType<typeof useUpdateCheck> | null>(null);

function AppShell({ children }: { children: React.ReactNode }) {
  const {isUpdateAvailable, latestVersion, downloadUrl, nativeUpdate, downloaded, installNow} = useContext(UpdateContext)!;
  const dismissed = useSettingsStore(s => s.dismissed_update_version);
  const updateSettings = useSettingsStore(s => s.updateSettings);
  return (
    <>
      <div className="app-shell">
        <a href="#main-content" className="skip-link">Ga naar hoofdinhoud</a>
        <TitleBar />
        <div style={{ flex: 1, display: "flex", minHeight: 0 }}>
          <Sidebar />
          <main className="app-main" id="main-content">
            <ProcessingBar />
            <OfflineQueueBanner />
            {isUpdateAvailable && latestVersion && dismissed !== latestVersion && <UpdateBanner downloaded={downloaded} onInstall={installNow} nativeUpdate={nativeUpdate} version={latestVersion} downloadUrl={downloadUrl} onDismiss={() => updateSettings({dismissed_update_version:latestVersion})} />}
            <div className="app-main-content">
              {children}
            </div>
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

      // Ctrl+1..6 mirrors the macOS navigation order
      if (ctrl && e.key === "1") { e.preventDefault(); navigate("/"); }
      if (ctrl && e.key === "2") { e.preventDefault(); navigate("/recording"); }
      if (ctrl && e.key === "3") { e.preventDefault(); navigate("/tasks"); }
      if (ctrl && e.key === "4") { e.preventDefault(); navigate("/transcripts"); }
      if (ctrl && e.key === "5") { e.preventDefault(); navigate("/people"); }
      if (ctrl && e.key === "6") { e.preventDefault(); navigate("/settings"); }

      // Ctrl+N = New recording
      if (ctrl && e.key === "n") { e.preventDefault(); navigate("/recording"); }

      // Ctrl+F = Focus search in transcripts
      if (ctrl && e.key === "f") { e.preventDefault(); navigate("/transcripts"); }

      // Escape = Close modals (handled by individual components)

      // Production document reload is denied by the native main navigation guard.
    }

    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [navigate]);

  return null;
}

function ProtectedRoutes() {
  const identityMissing = useSupportStore(s => !s.name.trim() || !isValidEmail(s.email));
  const { isAuthenticated, isInitializing } = useAuthStore();
  const { has_completed_onboarding, processing_mode, updateSettings } = useSettingsStore();
  const location = useLocation();
  useEffect(() => logRoute(location.pathname), [location.pathname]);
  const setProfiles = useProfilesStore((s) => s.setProfiles);
  const showLocalProfiles = useProfilesStore((s) => s.showLocalProfiles);

  const addBackgroundTask = useRecordingStore((s) => s.addBackgroundTask);
  const updateBackgroundTask = useRecordingStore((s) => s.updateBackgroundTask);
  const removeBackgroundTask = useRecordingStore((s) => s.removeBackgroundTask);
  const { addTranscript } = useTranscriptsStore();

  // Validate token on app start — show toast if invalid, never auto-logout
  const tokenValidatedRef = useRef(false);
  useEffect(() => {
    if (processing_mode === "local") {
      tokenValidatedRef.current = false;
      showLocalProfiles();
      return;
    }
    if (!isAuthenticated || tokenValidatedRef.current) return;
    let cancelled = false;
    tokenValidatedRef.current = true;
    api.getProfiles().then((profiles: Profile[]) => {
      if (!cancelled) setProfiles(currentProfileChoices(profiles));
    }).catch(() => {
      // Token may be invalid — show non-disruptive message
      useToast.getState().show("Sessie mogelijk verlopen. Log opnieuw in als er problemen zijn.", "warning");
    });
    api.getMySettings().then((settings) => {
      updateSettings({
        ms365_client_id: settings.ms365_client_id || undefined,
        ms365_tenant_id: settings.ms365_tenant_id || undefined,
      });
    }).catch(() => { /* ignore - settings will remain as-is */ });
    return () => { cancelled = true; };
  }, [isAuthenticated, processing_mode, setProfiles, showLocalProfiles, updateSettings]);

  // Global recording stop/error handler — always active, survives page navigation

  // Recover active tasks on app start via /tasks/active endpoint
  const recoveryRanRef = useRef(false);
  useEffect(() => {
    if (!isAuthenticated) return;
    if (recoveryRanRef.current) return;
    // Local mode has no server-side tasks to recover.
    if (processing_mode === "local") return;
    recoveryRanRef.current = true;

    (async () => {
      try {
        const activeTasks = await api.getActiveTasks();
        for (const task of activeTasks) {
          // Read now: another recovery response or the existing realm may already own this task.
          if (useRecordingStore.getState().backgroundTasks.some((current) => current.task_id === task.task_id)) continue;
          addBackgroundTask({
            task_id: task.task_id,
            status: task.status as "uploading",
            progress: task.progress ?? 0,
            mode: task.mode ?? ("microphone" as const),
            created_at: task.created_at,
          });

          const sseClient = createSSEClient(api.getStreamUrl(task.task_id));
          sseClient.connect(
            (update) => updateBackgroundTask(task.task_id, update),
            (err) => {
              console.error("[TaskRecovery] SSE error:", err);
              updateBackgroundTask(task.task_id, { status: "failed", error_message: "Verbinding verloren" });
            },
            async (status) => {
              if (status === "failed" || status === "cancelled" || status === "error") return;
              try {
                const transcripts = await api.getTranscripts();
                const completed = transcripts.find((t) => t.task_id === task.task_id || t.id === task.task_id);
                if (!completed) throw new Error("Het resultaat is nog niet beschikbaar. Vernieuw Notulen om het op te halen.");
                addTranscript(completed);
                removeBackgroundTask(task.task_id);
              } catch (error) {
                updateBackgroundTask(task.task_id, {
                  status: "failed",
                  error_message: error instanceof Error ? error.message : "Resultaat ophalen mislukt",
                });
              }
            }
          );
        }
      } catch {
        // Recovery failed — not critical
      }
    })();
  }, [isAuthenticated, processing_mode]);

  if (isInitializing && processing_mode !== "local") {
    return null;
  }

  if (!canOpenRoute(location.pathname, processing_mode, isAuthenticated)) {
    return <Navigate to="/login" replace />;
  }

  if (identityMissing) {
    return <div className="app-shell"><TitleBar /><IdentityGate /></div>;
  }

  if (!has_completed_onboarding && processing_mode !== "local") {
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
        <Route path="/tasks"       element={<TasksPage />} />
        <Route path="/transcripts" element={<TranscriptsPage />} />
        <Route path="/profiles"    element={<Navigate to="/settings?tab=notulen" replace />} />
        <Route path="/people"      element={<PeoplePage />} />
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
  const updates = useUpdateCheck();
  useEffect(startSupportOwner, []);
  useGlobalRecordingHandler();
  useSupportLifecycle();
  const [updateRequired, setUpdateRequired] = useState<{ current: string; minimum: string } | null>(null);
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

  // Force update check on launch (skip in browser dev mode)
  useEffect(() => {
    if (processingMode === "local") {
      setUpdateRequired(null);
      return;
    }
    if (!("__TAURI_INTERNALS__" in window)) return;
    let cancelled = false;
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

        if (isOutdated && !cancelled) {
          setUpdateRequired({ current: currentVersion, minimum: versionInfo.minimum_version });
        }
      } catch {
        // Version check failed — allow app to continue
      }
    })();
    return () => { cancelled = true; };
  }, [processingMode]);

  useEffect(() => {
    if (!("__TAURI_INTERNALS__" in window)) return;
    initMeetingNotifications().catch(() => {});
  }, []);

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

  // The approved desktop design uses the same night palette on every platform.
  useEffect(() => {
    document.documentElement.dataset.theme = "dark";
  }, []);

  // Handle Microsoft 365 OAuth deep-link callbacks
  // The deep-link plugin payload is a JSON array of URLs, e.g. ["transcript-studio://auth/callback?code=..."]
  useEffect(() => {
    const unlisten = listen<string>("oauth-callback", async (event) => {
      try {
        let callbackUrl = event.payload;
        // Payload from Rust may be a JSON array string — extract the URL
        try {
          const parsed = JSON.parse(callbackUrl);
          if (Array.isArray(parsed) && parsed.length > 0) callbackUrl = parsed[0];
        } catch { /* not JSON, use as-is */ }

        if (!callbackUrl?.startsWith("transcript-studio://auth/callback")) return;
        await MicrosoftGraphService.handleAuthCallback(callbackUrl);
      } catch (err) {
        console.error("[OAuth] Callback error:", err);
      }
    });
    return () => { unlisten.then((fn) => fn()); };
  }, []);

  if (updateRequired) {
    return <UpdateRequiredOverlay currentVersion={updateRequired.current} minimumVersion={updateRequired.minimum} />;
  }

  if (shouldBlockForLocalNotes(processingMode, localReady)) {
    return localLoadError ? (
      <div className="empty-state">
        <p>Lokale notulen konden niet worden geladen: {localLoadError}</p>
        <button className="btn btn-accent" onClick={() => void loadLocalNotes()}>Opnieuw proberen</button>
      </div>
    ) : null;
  }

  return (
    <UpdateContext.Provider value={updates}>
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
    </UpdateContext.Provider>
  );
}
