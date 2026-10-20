import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import App from "../App";
import { useAuthStore } from "../stores/authStore";
import { useSettingsStore } from "../stores/settingsStore";
import { useRecordingStore } from "../stores/recordingStore";
import { useTranscriptsStore } from "../stores/transcriptsStore";
import type { Transcript } from "../types";

const mocks = vi.hoisted(() => ({
  complete: undefined as undefined | ((status?: string) => Promise<void>),
  transcripts: vi.fn<() => Promise<Transcript[]>>(),
}));
vi.mock("../services/api", () => ({ api: {
  getProfiles: vi.fn(async () => []), getMySettings: vi.fn(async () => ({})),
  getActiveTasks: vi.fn(async () => [{ task_id: "recovered", status: "transcribing", created_at: "2026-10-19" }]),
  getStreamUrl: (id: string) => id, getTranscripts: mocks.transcripts,
} }));
vi.mock("../services/sse", () => ({ createSSEClient: () => ({ connect: (_update: unknown, _error: unknown, complete: (status?: string) => Promise<void>) => { mocks.complete = complete; } }) }));
vi.mock("@tauri-apps/api/event", () => ({ listen: vi.fn(async () => () => {}) }));
vi.mock("../services/crashReporter", () => ({ initCrashReporter: vi.fn() }));
vi.mock("../services/meetingNotifications", () => ({ initMeetingNotifications: vi.fn() }));
vi.mock("../services/microsoftGraph", () => ({ MicrosoftGraphService: {} }));
vi.mock("../services/offlineQueue", () => ({ getQueue: vi.fn(async () => []) }));
vi.mock("../stores/localTranscriptsStore", () => ({ useLocalTranscriptsStore: { getState: () => ({ hydrate: async () => {} }) } }));
vi.mock("../hooks/useGlobalRecordingHandler", () => ({ useGlobalRecordingHandler: vi.fn() }));
vi.mock("../hooks/useUpdateCheck", () => ({ useUpdateCheck: () => ({ isUpdateAvailable: false }) }));
vi.mock("../components/ui/UpdateBanner", () => ({ UpdateBanner: () => null }));
vi.mock("../components/layout/TitleBar", () => ({ TitleBar: () => null }));
vi.mock("../components/layout/Sidebar", () => ({ Sidebar: () => null }));
vi.mock("../components/calendar/CallAlertOverlay", () => ({ CallAlertOverlay: () => null }));
vi.mock("../components/ProcessingBar", () => ({ ProcessingBar: () => null }));
vi.mock("../components/onboarding/OnboardingWizard", () => ({ OnboardingWizard: () => null }));
vi.mock("../pages/LoginPage", () => ({ LoginPage: () => null }));
vi.mock("../pages/HomePage", () => ({ HomePage: () => null }));
vi.mock("../pages/RecordingPage", () => ({ RecordingPage: () => null }));
vi.mock("../pages/TranscriptsPage", () => ({ TranscriptsPage: () => null }));
vi.mock("../pages/AccountPage", () => ({ AccountPage: () => null }));
vi.mock("../pages/SettingsPage", () => ({ SettingsPage: () => null }));
vi.mock("../pages/AdminPage", () => ({ AdminPage: () => null }));
vi.mock("../pages/TasksPage", () => ({ TasksPage: () => null }));
vi.mock("../pages/PeoplePage", () => ({ PeoplePage: () => null }));

let root: Root;
beforeEach(async () => {
  mocks.complete = undefined;
  useAuthStore.setState({ isAuthenticated: true, isInitializing: false });
  useSettingsStore.setState({ processing_mode: "cloud", has_completed_onboarding: true });
  useRecordingStore.setState({ backgroundTasks: [] });
  useTranscriptsStore.setState({ transcripts: [] });
  root = createRoot(document.createElement("div"));
  await act(async () => root.render(<App />));
  expect(mocks.complete).toBeTypeOf("function");
});
afterEach(async () => { await act(async () => root.unmount()); vi.clearAllMocks(); });
const unrelated = { id: "other", task_id: "other-task" } as Transcript;

it.each(["task_id", "id"] as const)("recovers the matching %s result even when another result is first", async (key) => {
  const result = { id: "result", [key]: "recovered" } as Transcript;
  mocks.transcripts.mockResolvedValue([unrelated, result]);
  await act(async () => { await mocks.complete!(); });
  expect(useTranscriptsStore.getState().transcripts).toEqual([result]);
  expect(useRecordingStore.getState().backgroundTasks).toEqual([]);
});
it("keeps a visible failure when the recovered result is not available yet", async () => {
  mocks.transcripts.mockResolvedValue([unrelated]);
  await act(async () => { await mocks.complete!(); });
  expect(useTranscriptsStore.getState().transcripts).toEqual([]);
  expect(useRecordingStore.getState().backgroundTasks).toEqual([expect.objectContaining({ task_id: "recovered", status: "failed", error_message: expect.stringContaining("resultaat") })]);
});
it("handles failure to fetch the recovered result without losing the task", async () => {
  mocks.transcripts.mockRejectedValue(new Error("Server tijdelijk onbereikbaar"));
  await act(async () => { await mocks.complete!(); });
  expect(useTranscriptsStore.getState().transcripts).toEqual([]);
  expect(useRecordingStore.getState().backgroundTasks).toEqual([expect.objectContaining({ task_id: "recovered", status: "failed", error_message: "Server tijdelijk onbereikbaar" })]);
});

it("recovers server tasks when an authenticated user switches from local to cloud mode", async () => {
  await act(async () => root.unmount());
  mocks.complete = undefined;
  useSettingsStore.setState({ processing_mode: "local" });
  root = createRoot(document.createElement("div"));
  await act(async () => root.render(<App />));
  expect(mocks.complete).toBeUndefined();
  await act(async () => { useSettingsStore.setState({ processing_mode: "cloud" }); });
  expect(mocks.complete).toBeTypeOf("function");
});

it.each(["failed", "cancelled", "error"])("preserves a recovered %s task and its server error instead of fetching a partial result", async (status) => {
  await act(async () => { useRecordingStore.getState().updateBackgroundTask("recovered", { status: status as "failed", error_message: "Eigen QA-serverfout" }); });
  mocks.transcripts.mockResolvedValue([{ id: "partial", task_id: "recovered" } as Transcript]);
  await act(async () => { await mocks.complete!(status); });
  expect(mocks.transcripts).not.toHaveBeenCalled();
  expect(useTranscriptsStore.getState().transcripts).toEqual([]);
  expect(useRecordingStore.getState().backgroundTasks).toEqual([expect.objectContaining({ task_id: "recovered", status, error_message: "Eigen QA-serverfout" })]);
});
