import { afterEach, expect, it } from "vitest";
import { act } from "react";
import { createRoot } from "react-dom/client";
import { TasksPage } from "../TasksPage";
import { useSettingsStore } from "../../stores/settingsStore";
import { useRecordingStore } from "../../stores/recordingStore";
import { useTaskHistory } from "../../services/taskHistory";
import { MemoryRouter } from "react-router-dom";

afterEach(() => {
  useRecordingStore.setState({ backgroundTasks: [] });
  useTaskHistory.setState({ entries: [], pendingTitles: {} });
  useSettingsStore.getState().updateSettings({ processing_mode: "cloud" });
});

it("shows a failed local processing task and its retry action on Taken", async () => {
  useSettingsStore.getState().updateSettings({ processing_mode: "local" });
  useRecordingStore.getState().addBackgroundTask({
    task_id: "local-test",
    status: "failed",
    progress: 55,
    mode: "microphone",
    profile_id: "zakelijk",
    local_audio_path: "C:\\Recordings\\meeting.wav",
    error_message: "Notule genereren mislukt",
    created_at: new Date().toISOString(),
  });

  const container = document.createElement("div");
  const root = createRoot(container);
  await act(async () => { root.render(<MemoryRouter><TasksPage /></MemoryRouter>); });
  const html = container.innerHTML;
  expect(html).toContain("Notule genereren mislukt");
  expect(html).toContain("Opnieuw verwerken");
  expect(html).not.toContain("Geen actieve taken");
  // A finished task is listed once, under Geschiedenis, with its actions.
  expect(html).toContain("Geschiedenis");
  expect(html.match(/Notule genereren mislukt/g)).toHaveLength(1);
  expect(html).toContain("Opname verwijderen");
  expect(html).toContain("Details");
  await act(async () => { root.unmount(); });
});

it("keeps the history after the task left the active list", async () => {
  useSettingsStore.getState().updateSettings({ processing_mode: "local" });
  const rec = useRecordingStore.getState();
  rec.addBackgroundTask({ task_id: "local-done", status: "transcribing", progress: 10, mode: "microphone",
    filename: "weekstart.wav", local_audio_path: "C:\\Recordings\\weekstart.wav", created_at: new Date().toISOString() });
  rec.updateBackgroundTask("local-done", { status: "completed", progress: 100, extracted_title: "Weekstart" });
  rec.removeBackgroundTask("local-done");
  const container = document.createElement("div");
  const root = createRoot(container);
  await act(async () => { root.render(<MemoryRouter><TasksPage /></MemoryRouter>); });
  expect(container.innerHTML).toContain("Weekstart");
  expect(container.innerHTML).toContain("Voltooid");
  expect(container.innerHTML).not.toContain("Geen actieve taken");
  await act(async () => { root.unmount(); });
});

it("shows an app regeneration task even when cloud mode is selected", async () => {
  useSettingsStore.getState().updateSettings({ processing_mode: "cloud" });
  useRecordingStore.getState().addBackgroundTask({
    task_id: "regen-old-document", status: "generating", progress: 50,
    mode: "microphone", extracted_title: "Oud document", created_at: new Date().toISOString(),
  });
  const container = document.createElement("div");
  const root = createRoot(container);
  await act(async () => { root.render(<MemoryRouter><TasksPage /></MemoryRouter>); });
  expect(container.innerHTML).toContain("Oud document");
  expect(container.innerHTML).toContain("Notulen genereren");
  await act(async () => { root.unmount(); });
});
