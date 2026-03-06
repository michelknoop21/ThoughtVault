import { BrowserRouter, Routes, Route, Navigate, useNavigate } from "react-router-dom";
import { useEffect } from "react";
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
import { SettingsPage } from "./pages/SettingsPage";
import { AdminPage } from "./pages/AdminPage";
import { OnboardingWizard } from "./components/onboarding/OnboardingWizard";
import { useAuthStore } from "./stores/authStore";
import { useSettingsStore } from "./stores/settingsStore";
import { useProfilesStore } from "./stores/profilesStore";
import { MicrosoftGraphService } from "./services/microsoftGraph";
import { api } from "./services/api";
import type { Profile } from "./types";

function AppShell({ children }: { children: React.ReactNode }) {
  return (
    <div className="app-shell" style={{ borderRadius: 8, overflow: "hidden" }}>
      <TitleBar />
      <div style={{ flex: 1, display: "flex", overflow: "hidden" }}>
        <Sidebar />
        <main
          style={{
            flex: 1,
            display: "flex",
            flexDirection: "column",
            overflow: "hidden",
            background: "var(--bg-solid-secondary)",
          }}
        >
          <div style={{ flex: 1, display: "flex", flexDirection: "column", overflow: "hidden" }}>
            {children}
          </div>
          <YingaFooter compact />
        </main>
      </div>
      {/* Calendar call alert — overlays on top of content */}
      <CallAlertOverlay />
    </div>
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

      // Ctrl+1..4 = Navigate tabs
      if (ctrl && e.key === "1") { e.preventDefault(); navigate("/"); }
      if (ctrl && e.key === "2") { e.preventDefault(); navigate("/recording"); }
      if (ctrl && e.key === "3") { e.preventDefault(); navigate("/transcripts"); }
      if (ctrl && e.key === "4") { e.preventDefault(); navigate("/settings"); }

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
      <div className="app-shell" style={{ borderRadius: 8, overflow: "hidden" }}>
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
        <Route path="/settings"    element={<SettingsPage />} />
        <Route path="/admin"       element={<AdminPage />} />
        <Route path="*"            element={<Navigate to="/" replace />} />
      </Routes>
    </AppShell>
  );
}

export default function App() {
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
