import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { useSupportStore } from "../stores/supportStore";
import App from "../App";
import { useAuthStore } from "../stores/authStore";
import { useSettingsStore } from "../stores/settingsStore";
import { useRecordingStore } from "../stores/recordingStore";
import { useTranscriptsStore } from "../stores/transcriptsStore";
import type { Transcript } from "../types";
import { useSupportLifecycle } from "../hooks/useSupportLifecycle";

const mocks = vi.hoisted(() => ({
  complete: undefined as undefined | ((status?: string) => Promise<void>),
  hydrate: vi.fn(async () => {}),
  transcripts: vi.fn<() => Promise<Transcript[]>>(),
  active: vi.fn(async () => [{ task_id: "recovered", status: "transcribing", created_at: "2026-10-19" }]),
  connect: vi.fn(),
  failChild: false,
  rootMounts: 0,
  rootCleanups: 0,
}));
vi.mock("../services/api", () => ({ api: {
  getProfiles: vi.fn(async () => []), getMySettings: vi.fn(async () => ({})),
  getActiveTasks: mocks.active,
  getStreamUrl: (id: string) => id, getTranscripts: mocks.transcripts,
} }));
vi.mock("../services/sse", () => ({ createSSEClient: () => ({ connect: (_update: unknown, _error: unknown, complete: (status?: string) => Promise<void>) => { mocks.complete = complete; mocks.connect(); } }) }));
vi.mock("@tauri-apps/api/event", () => ({ listen: vi.fn(async () => () => {}) }));
vi.mock("../services/crashReporter", () => ({
  initCrashReporter: vi.fn(), reportFailure: vi.fn(async () => {}), markStage: vi.fn(),
  stageForStatus: () => null, failureFromTransition: () => null,
}));
vi.mock("../services/meetingNotifications", () => ({ initMeetingNotifications: vi.fn() }));
vi.mock("../services/microsoftGraph", () => ({ MicrosoftGraphService: {} }));
vi.mock("../services/offlineQueue", () => ({ getQueue: vi.fn(async () => []) }));
vi.mock("../stores/localTranscriptsStore", () => ({ useLocalTranscriptsStore: { getState: () => ({ hydrate: mocks.hydrate }) } }));
vi.mock("../hooks/useSupportLifecycle", () => ({ useSupportLifecycle: vi.fn() }));
vi.mock("../hooks/useGlobalRecordingHandler", async () => {
  const { useEffect } = await import("react");
  return { useGlobalRecordingHandler: () => useEffect(() => {
    mocks.rootMounts++;
    return () => { mocks.rootCleanups++; };
  }, []) };
});
vi.mock("../hooks/useUpdateCheck", () => ({ useUpdateCheck: () => ({ isUpdateAvailable: false, downloaded: false, installNow: async () => {} }) }));
vi.mock("../components/ui/UpdateBanner", () => ({ UpdateBanner: () => null }));
vi.mock("../components/layout/TitleBar", () => ({ TitleBar: () => null }));
vi.mock("../components/layout/Sidebar", () => ({ Sidebar: () => null }));
vi.mock("../components/calendar/CallAlertOverlay", () => ({ CallAlertOverlay: () => null }));
vi.mock("../components/ProcessingBar", () => ({ ProcessingBar: () => null }));
vi.mock("../components/support/IdentityGate", () => ({ IdentityGate: () => <p>naamscherm</p> }));
vi.mock("../components/onboarding/OnboardingWizard", () => ({ OnboardingWizard: () => <p>onboarding</p> }));
vi.mock("../pages/LoginPage", () => ({ LoginPage: () => null }));
vi.mock("../pages/HomePage", () => ({ HomePage: () => {
  if (mocks.failChild) throw new Error("Transient child failure");
  return null;
} }));
vi.mock("../pages/RecordingPage", () => ({ RecordingPage: () => null }));
vi.mock("../pages/TranscriptsPage", () => ({ TranscriptsPage: () => null }));
vi.mock("../pages/AccountPage", () => ({ AccountPage: () => null }));
vi.mock("../pages/SettingsPage", () => ({ SettingsPage: () => null }));
vi.mock("../pages/AdminPage", () => ({ AdminPage: () => null }));
vi.mock("../pages/TasksPage", () => ({ TasksPage: () => null }));
vi.mock("../pages/PeoplePage", () => ({ PeoplePage: () => null }));

let root: Root;
beforeEach(async () => {
  useSupportStore.setState({ name: "Test", email: "test@example.com" });
  mocks.complete = undefined;
  mocks.failChild = false;
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
  useRecordingStore.setState({ backgroundTasks: [] });
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


it("keeps support lifecycle mounted while local notes are still loading", async () => {
  await act(async () => root.unmount());
  let finish!: () => void;
  mocks.hydrate.mockImplementationOnce(() => new Promise<void>(resolve => { finish = resolve; }));
  useSettingsStore.setState({ processing_mode: "local" });
  vi.mocked(useSupportLifecycle).mockClear();
  const host = document.createElement("div");
  root = createRoot(host);
  await act(async () => root.render(<App />));
  expect(host.textContent).toBe("");
  expect(useSupportLifecycle).toHaveBeenCalled();
  await act(async () => finish());
});

it("keeps support lifecycle mounted at the unauthenticated login route", async () => {
  await act(async () => root.unmount());
  useAuthStore.setState({ isAuthenticated: false, isInitializing: false });
  window.history.replaceState({}, "", "/login");
  vi.mocked(useSupportLifecycle).mockClear();
  root = createRoot(document.createElement("div"));
  await act(async () => root.render(<App />));
  expect(useSupportLifecycle).toHaveBeenCalled();
  window.history.replaceState({}, "", "/");
});

it("keeps the root recording owner and existing cloud SSE through child recovery", async () => {
  await act(async () => { useRecordingStore.getState().updateBackgroundTask("recovered", { status: "generating", progress: 63 }); });
  const ownedTask = useRecordingStore.getState().backgroundTasks[0];
  const completion = mocks.complete;
  await act(async () => root.unmount());
  const host = document.createElement("div");
  root = createRoot(host);
  const connections = mocks.connect.mock.calls.length;
  await act(async () => root.render(<App />));
  const mounts = mocks.rootMounts;
  const cleanups = mocks.rootCleanups;
  const consoleError = vi.spyOn(console, "error").mockImplementation(() => {});
  mocks.failChild = true;
  await act(async () => root.render(<App />));
  expect(host.textContent).toContain("Opnieuw proberen");
  mocks.failChild = false;
  await act(async () => { Array.from(host.querySelectorAll("button")).find(button => button.textContent === "Opnieuw proberen")!.click(); });
  expect(mocks.rootMounts).toBe(mounts);
  expect(mocks.rootCleanups).toBe(cleanups);
  expect(mocks.connect).toHaveBeenCalledTimes(connections);
  expect(useRecordingStore.getState().backgroundTasks).toEqual([ownedTask]);
  expect(useRecordingStore.getState().backgroundTasks[0]).toMatchObject({ status: "generating", progress: 63 });
  expect(mocks.complete).toBe(completion);
  consoleError.mockRestore();
});

it("claims a task only once when two recovery requests settle after a boundary remount", async () => {
  await act(async () => root.unmount());
  useRecordingStore.setState({ backgroundTasks: [] });
  type ActiveTasks = Awaited<ReturnType<typeof mocks.active>>;
  const pending: Array<(tasks: ActiveTasks) => void> = [];
  mocks.active.mockImplementationOnce(() => new Promise(resolve => pending.push(resolve)))
    .mockImplementationOnce(() => new Promise(resolve => pending.push(resolve)));
  const host = document.createElement("div");
  root = createRoot(host);
  const consoleError = vi.spyOn(console, "error").mockImplementation(() => {});
  await act(async () => root.render(<App />));
  mocks.failChild = true;
  await act(async () => root.render(<App />));
  mocks.failChild = false;
  await act(async () => { Array.from(host.querySelectorAll("button")).find(button => button.textContent === "Opnieuw proberen")!.click(); });
  expect(pending).toHaveLength(2);
  const connections = mocks.connect.mock.calls.length;
  await act(async () => {
    for (const resolve of pending) resolve([{ task_id: "race", status: "transcribing", created_at: "2026-11-10" }]);
  });
  expect(useRecordingStore.getState().backgroundTasks).toEqual([expect.objectContaining({ task_id: "race" })]);
  expect(mocks.connect).toHaveBeenCalledTimes(connections + 1);
  consoleError.mockRestore();
});

it.each([
  ["", "test@example.com"], ["Test", ""], ["Test", "test@"], ["   ", "test@example.com"],
])("requires identity for existing local users (%s, %s)", async (name, email) => {
  await act(async () => root.unmount());
  useSettingsStore.setState({ processing_mode: "local", has_completed_onboarding: true });
  useSupportStore.setState({ name, email });
  const host = document.createElement("div");
  root = createRoot(host);
  const mounts = mocks.rootMounts;
  vi.mocked(useSupportLifecycle).mockClear();
  await act(async () => root.render(<App />));
  expect(mocks.rootMounts).toBe(mounts + 1);
  expect(useSupportLifecycle).toHaveBeenCalled();
  expect(host.textContent).toContain("naamscherm");
});

it("gates before cloud onboarding without stopping recovered task hooks", async () => {
  await act(async () => root.unmount());
  useSupportStore.setState({ name: "", email: "" });
  useSettingsStore.setState({ has_completed_onboarding: false });
  const host = document.createElement("div");
  root = createRoot(host);
  const mounts = mocks.rootMounts;
  vi.mocked(useSupportLifecycle).mockClear();
  await act(async () => root.render(<App />));
  expect(mocks.rootMounts).toBe(mounts + 1);
  expect(useSupportLifecycle).toHaveBeenCalled();
  expect(host.textContent).toContain("naamscherm");
  expect(host.textContent).not.toContain("onboarding");
  expect(mocks.complete).toBeTypeOf("function");
  await act(async () => useSupportStore.setState({ name: "Test", email: "test@example.com" }));
  expect(host.textContent).toContain("onboarding");
});
