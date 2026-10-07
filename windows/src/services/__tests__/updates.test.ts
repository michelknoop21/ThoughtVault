import { describe, expect, it } from "vitest";
import { updateIsBusy } from "../../components/ui/UpdateBanner";
import { useRecordingStore } from "../../stores/recordingStore";
import { recordingAction } from "../recordingActions";

describe("update installation guard", () => {
  it("blocks recordings, pending processing and new starts during installation", async () => {
    const idle = { phase: "idle" as const, backgroundTasks: [], isSubmittingYouTube: false };
    expect(updateIsBusy(idle)).toBe(false);
    for (const phase of ["preparing", "recording", "paused", "stopping", "uploading"] as const) {
      expect(updateIsBusy({ ...idle, phase })).toBe(true);
    }
    expect(updateIsBusy({ ...idle, isSubmittingYouTube: true })).toBe(true);
    const task = { task_id: "test", status: "generating" } as never;
    expect(updateIsBusy({ ...idle, backgroundTasks: [task] })).toBe(true);
    useRecordingStore.setState({ updateInstalling: true });
    try { await expect(recordingAction("start")).rejects.toThrow("bijgewerkt"); }
    finally { useRecordingStore.setState({ updateInstalling: false }); }
  });
});
