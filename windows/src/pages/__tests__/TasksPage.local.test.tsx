import { afterEach, expect, it } from "vitest";
import { act } from "react";
import { createRoot } from "react-dom/client";
import { TasksPage } from "../TasksPage";
import { useSettingsStore } from "../../stores/settingsStore";
import { useRecordingStore } from "../../stores/recordingStore";

afterEach(() => {
  useRecordingStore.setState({ backgroundTasks: [] });
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
  await act(async () => { root.render(<TasksPage />); });
  const html = container.innerHTML;
  expect(html).toContain("Notule genereren mislukt");
  expect(html).toContain("Opnieuw verwerken");
  expect(html).not.toContain("Geen actieve taken");
  await act(async () => { root.unmount(); });
});
