import { BrowserRouter, Routes, Route, Navigate } from "react-router-dom";
import { useEffect } from "react";
import { listen } from "@tauri-apps/api/event";
import { TitleBar } from "./components/layout/TitleBar";
import { Sidebar } from "./components/layout/Sidebar";
import { CallAlertOverlay } from "./components/calendar/CallAlertOverlay";
import { LoginPage } from "./pages/LoginPage";
import { HomePage } from "./pages/HomePage";
import { RecordingPage } from "./pages/RecordingPage";
import { TranscriptsPage } from "./pages/TranscriptsPage";
import { SettingsPage } from "./pages/SettingsPage";
import { AdminPage } from "./pages/AdminPage";
import { OnboardingWizard } from "./components/onboarding/OnboardingWizard";
import { useAuthStore } from "./stores/authStore";
import { useSettingsStore } from "./stores/settingsStore";
import { MicrosoftGraphService } from "./services/microsoftGraph";

function AppShell({ children }: { children: React.ReactNode }) {
  return (
    <div className="app-shell" style={{ borderRadius: 8, overflow: "hidden" }}>
      <TitleBar />
      <div style={{ flex: 1, display: "flex", overflow: "hidden" }}>
        <Sidebar />
        <main
          style={{
            flex: 1,
            overflow: "auto",
            background: "var(--bg-solid-secondary)",
          }}
        >
          {children}
        </main>
      </div>
      {/* Calendar call alert — overlays on top of content */}
      <CallAlertOverlay />
    </div>
  );
}

function ProtectedRoutes() {
  const { isAuthenticated } = useAuthStore();
  const { has_completed_onboarding } = useSettingsStore();

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
    <BrowserRouter>
      <div style={{ height: "100%" }}>
        <Routes>
          <Route path="/login" element={<LoginPage />} />
          <Route path="/*"     element={<ProtectedRoutes />} />
        </Routes>
      </div>
    </BrowserRouter>
  );
}
