import { BrowserRouter, Routes, Route, Navigate, useNavigate } from "react-router-dom";
import { useEffect, useRef, useState } from "react";
import { listen } from "@tauri-apps/api/event";
import { TitleBar } from "./components/layout/TitleBar";
import { Sidebar } from "./components/layout/Sidebar";
import { CallAlertOverlay } from "./components/calendar/CallAlertOverlay";
import { BrandFooter } from "./components/brand/BrandFooter";
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
import { TasksPage } from "./pages/TasksPage";
import { PeoplePage } from "./pages/PeoplePage";
import FeedbackWidget from "./components/FeedbackWidget";
import { ProcessingBar } from "./components/ProcessingBar";
import { OnboardingWizard } from "./components/onboarding/OnboardingWizard";
import { useAuthStore } from "./stores/authStore";
import { useSettingsStore } from "./stores/settingsStore";
import { useProfilesStore } from "./stores/profilesStore";
import { useRecordingStore } from "./stores/recordingStore";
import { useTranscriptsStore } from "./stores/transcriptsStore";
import { MicrosoftGraphService } from "./services/microsoftGraph";
import { api } from "./services/api";
import { createSSEClient } from "./services/sse";
import { initCrashReporter } from "./services/crashReporter";
import { initMeetingNotifications } from "./services/meetingNotifications";
import { useUploadQueueStore } from "./stores/uploadQueueStore";
import { useGlobalRecordingHandler } from "./hooks/useGlobalRecordingHandler";
import { useToast } from "./components/ui/InfoBar";
import type { Profile } from "./types";

initCrashReporter();

function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(0)} KB`;
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(1)} GB`;
}

function OfflineQueueBanner() {
  const [count, setCount] = useState(0);
  const [processing, setProcessing] = useState(false);
  const isProcessingRef = useRef(false);

  // Upload queue progress state
  const currentItem = useUploadQueueStore((s) => s.currentItem);
  const progress = useUploadQueueStore((s) => s.progress);
  const uploadSpeed = useUploadQueueStore((s) => s.uploadSpeed);
  const queueItems = useUploadQueueStore((s) => s.items);
  const permanentlyFailed = useUploadQueueStore((s) => s.permanentlyFailed);
  const clearPermanentlyFailed = useUploadQueueStore((s) => s.clearPermanentlyFailed);
  const resetQueueStore = useUploadQueueStore((s) => s.reset);
  const processingMode = useSettingsStore((s) => s.processing_mode);

  async function handleClearQueue() {
    try {
      const { clearQueue } = await import("./services/offlineQueue");
      await clearQueue();
    } catch { /* best-effort */ }
    resetQueueStore();
    setCount(0);
  }

  useEffect(() => {
    // The server upload queue only exists in cloud mode.
    if (processingMode === "local") return;
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
  }, [processingMode]);

  // Never surface the server upload queue in local mode.
  if (processingMode === "local") return null;

  // Use queueItems count if available, otherwise fallback to poll count
  const displayCount = queueItems.length > 0 ? queueItems.length : count;

  // Show permanently failed warning even when queue is empty
  if (displayCount === 0 && !currentItem && permanentlyFailed.length === 0) return null;

  // Permanently failed items warning
  if (displayCount === 0 && !currentItem && permanentlyFailed.length > 0) {
    return (
      <div style={{
        padding: "8px 14px",
        background: "var(--fill-warning, #b45309)",
        color: "#fff",
        fontSize: 12,
        fontWeight: 500,
        flexShrink: 0,
      }}>
        <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
          <span style={{ flex: 1 }}>
            {permanentlyFailed.map((item) => (
              <div key={item.id}>
                '{item.fileName}' kon na meerdere pogingen niet worden ge&uuml;pload. Ga naar Opgeslagen opnames om het handmatig te proberen.
              </div>
            ))}
          </span>
          <button
            onClick={clearPermanentlyFailed}
            style={{ background: "none", border: "none", color: "#fff", cursor: "pointer", fontSize: 14, padding: "2px 6px" }}
          >
            &times;
          </button>
        </div>
      </div>
    );
  }

  const fileName = currentItem?.file_name || currentItem?.file_path?.split(/[\\/]/).pop();
  const fileSize = currentItem?.file_size_bytes;
  const currentIndex = currentItem ? queueItems.findIndex((i) => i.id === currentItem.id) + 1 : 0;

  return (
    <div style={{
      padding: "8px 14px",
      background: "var(--fill-accent-default)",
      color: "#fff",
      fontSize: 12,
      fontWeight: 500,
      flexShrink: 0,
    }}>
      <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
        <span className="status-pulse" style={{ width: 8, height: 8, borderRadius: "50%", background: "#fff" }} />
        <span style={{ flex: 1 }}>
          {processing && currentItem ? (
            <>
              Uploaden: {fileName && <span>{fileName}</span>}
              {fileSize ? ` (${formatBytes(fileSize)})` : ""}
              {" · "}
              {progress}%
              {uploadSpeed > 0 && ` (${formatBytes(uploadSpeed)}/s)`}
              {displayCount > 1 && ` [${currentIndex}/${displayCount}]`}
            </>
          ) : processing ? (
            `${displayCount} opname${displayCount !== 1 ? "s" : ""} worden verstuurd...`
          ) : (
            `${displayCount} opname${displayCount !== 1 ? "s" : ""} in wachtrij, wordt automatisch verstuurd`
          )}
        </span>
        {!processing && displayCount > 0 && (
          <button
            onClick={handleClearQueue}
            title="Wachtrij leegmaken"
            style={{ background: "rgba(255,255,255,0.2)", border: "1px solid rgba(255,255,255,0.3)", color: "#fff", cursor: "pointer", fontSize: 11, fontWeight: 600, padding: "2px 8px", borderRadius: 4, flexShrink: 0 }}
          >
            Leegmaken
          </button>
        )}
      </div>
      {processing && currentItem && (
        <div style={{
          marginTop: 4,
          height: 3,
          borderRadius: 2,
          background: "rgba(255,255,255,0.25)",
          overflow: "hidden",
        }}>
          <div style={{
            height: "100%",
            width: `${progress}%`,
            background: "#fff",
            borderRadius: 2,
            transition: "width 300ms ease",
          }} />
        </div>
      )}
    </div>
  );
}

function AppShell({ children }: { children: React.ReactNode }) {
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
            <div className="app-main-content">
              {children}
            </div>
            <BrandFooter compact />
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
  const { isAuthenticated, isInitializing } = useAuthStore();
  const { has_completed_onboarding, updateSettings } = useSettingsStore();
  const setProfiles = useProfilesStore((s) => s.setProfiles);

  const addBackgroundTask = useRecordingStore((s) => s.addBackgroundTask);
  const updateBackgroundTask = useRecordingStore((s) => s.updateBackgroundTask);
  const removeBackgroundTask = useRecordingStore((s) => s.removeBackgroundTask);
  const { addTranscript } = useTranscriptsStore();

  // Validate token on app start — show toast if invalid, never auto-logout
  const tokenValidatedRef = useRef(false);
  useEffect(() => {
    if (!isAuthenticated || tokenValidatedRef.current) return;
    tokenValidatedRef.current = true;
    api.getProfiles().then((profiles: Profile[]) => {
      if (profiles.length > 0) setProfiles(profiles);
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
  }, [isAuthenticated, setProfiles, updateSettings]);

  // Global recording stop/error handler — always active, survives page navigation
  useGlobalRecordingHandler();

  // Recover active tasks on app start via /tasks/active endpoint
  const recoveryRanRef = useRef(false);
  useEffect(() => {
    if (!isAuthenticated) return;
    if (recoveryRanRef.current) return;
    // Local mode has no server-side tasks to recover.
    if (useSettingsStore.getState().processing_mode === "local") return;
    recoveryRanRef.current = true;

    (async () => {
      try {
        const activeTasks = await api.getActiveTasks();
        for (const task of activeTasks) {
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
            async () => {
              const transcripts = await api.getTranscripts();
              if (transcripts[0]) addTranscript(transcripts[0]);
              removeBackgroundTask(task.task_id);
            }
          );
        }
      } catch {
        // Recovery failed — not critical
      }
    })();
  }, [isAuthenticated]);

  if (isInitializing) {
    return null;
  }

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
        <Route path="/tasks"       element={<TasksPage />} />
        <Route path="/transcripts" element={<TranscriptsPage />} />
        <Route path="/profiles"    element={<ProfilesPage />} />
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
