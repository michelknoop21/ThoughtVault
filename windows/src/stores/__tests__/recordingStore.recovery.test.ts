import { expect, it } from "vitest";
import { useRecordingStore } from "../recordingStore";
it("restores interrupted tasks as retryable failures without transcript payloads", async () => {
  localStorage.setItem("processing-recovery", JSON.stringify({ state: { backgroundTasks: [{ task_id: "local-interrupted", status: "generating", progress: 55, mode: "microphone", created_at: "2026-10-07", local_audio_path: "C:/test.wav" }] }, version: 0 }));
  await useRecordingStore.persist.rehydrate();
  expect(useRecordingStore.getState().backgroundTasks[0]).toMatchObject({ status: "failed", local_audio_path: "C:/test.wav" });
  useRecordingStore.getState().addBackgroundTask({ task_id: "local-interrupted", status: "generating", progress: 55, mode: "microphone", created_at: "2026-10-07", raw_transcription: "private text", notule_html: "private html" });
  expect(useRecordingStore.getState().backgroundTasks).toHaveLength(1);
  expect(localStorage.getItem("processing-recovery")).not.toContain("private text");
  expect(localStorage.getItem("processing-recovery")).not.toContain("private html");
});
