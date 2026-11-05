import { act } from "react";
import { createRoot } from "react-dom/client";
import { expect, it, vi } from "vitest";
import { SavedRecordings } from "../SavedRecordings";

const mocks = vi.hoisted(() => ({
  confirm: vi.fn(), delete: vi.fn(async () => {}), cleanup: vi.fn(async () => 1),
}));
vi.mock("../../ui/useConfirmation", () => ({ useConfirmation: () => ({ confirm: mocks.confirm, confirmation: null }) }));
vi.mock("../../ui/InfoBar", () => ({ useToast: () => ({ show: vi.fn() }) }));
vi.mock("../../../stores/settingsStore", () => ({ useSettingsStore: () => ({ processing_mode: "local" }) }));
vi.mock("../../../services/localPipeline", () => ({ processLocally: vi.fn() }));
vi.mock("../../../services/uploadAndTrack", () => ({ uploadAndTrack: vi.fn() }));
vi.mock("../../../services/tauriCommands", () => ({
  getRecordingsDir: vi.fn(async () => "recordings"),
  listRecordings: vi.fn(async () => [{ path: "recordings/qa.wav", filename: "qa.wav", created_at: 1, size_bytes: 100, duration_seconds: 1 }]),
  deleteRecording: mocks.delete, cleanupOldRecordings: mocks.cleanup,
}));

it("requires explicit confirmation before deleting one recording or cleaning old recordings", async () => {
  const container = document.createElement("div");
  const root = createRoot(container);
  await act(async () => root.render(<SavedRecordings initiallyExpanded />));
  mocks.confirm.mockResolvedValue(false);
  await act(async () => (container.querySelector('[title="Verwijderen"]') as HTMLElement).click());
  await act(async () => (container.querySelector('[title="Opnames ouder dan 7 dagen verwijderen"]') as HTMLElement).click());
  expect(mocks.delete).not.toHaveBeenCalled();
  expect(mocks.cleanup).not.toHaveBeenCalled();
  mocks.confirm.mockResolvedValue(true);
  await act(async () => (container.querySelector('[title="Verwijderen"]') as HTMLElement).click());
  expect(mocks.delete).toHaveBeenCalledWith("recordings/qa.wav");
  await act(async () => (container.querySelector('[title="Opnames ouder dan 7 dagen verwijderen"]') as HTMLElement).click());
  expect(mocks.cleanup).toHaveBeenCalledWith("recordings", 7);
  await act(async () => root.unmount());
});
