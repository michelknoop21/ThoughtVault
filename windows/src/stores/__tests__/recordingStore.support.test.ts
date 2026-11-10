import { afterEach, expect, it, vi } from "vitest";
import { useRecordingStore } from "../recordingStore";
import { failureFromTransition, markStage, reportFailure } from "../../services/crashReporter";
import type { TranscriptTask } from "../../types";

vi.mock("../../services/crashReporter", async original => ({
  ...(await original<object>()), reportFailure: vi.fn(async () => {}), markStage: vi.fn(),
}));
afterEach(() => { useRecordingStore.setState({ backgroundTasks: [] }); vi.clearAllMocks(); });
function add() {
  useRecordingStore.getState().addBackgroundTask({ task_id: "t", status: "transcribing", progress: 0, mode: "combined", created_at: "2026-11-10" } as TranscriptTask);
  return useRecordingStore.getState();
}
it("captures the previous stage, reports once across terminal repeats, and retains private UI bodies", () => {
  const state = add();
  state.updateBackgroundTask("t", { status: "generating" });
  expect(markStage).toHaveBeenLastCalledWith("notule");
  state.updateBackgroundTask("t", { status: "failed", error_message: "PRIVATE_PROVIDER_BODY" });
  state.updateBackgroundTask("t", { status: "failed", error_message: "PRIVATE_SSE_BODY" });
  state.updateBackgroundTask("t", { status: "error" });
  expect(reportFailure).toHaveBeenCalledExactlyOnceWith("notule", "Verwerking mislukt", "background_task_failed");
  expect(useRecordingStore.getState().backgroundTasks[0].error_message).toBe("PRIVATE_SSE_BODY");
  expect(markStage).toHaveBeenLastCalledWith(null);
});
it.each(["Geannuleerd door gebruiker.", "Vul je OpenAI API-sleutel in bij Instellingen.",
  "Vul je Ollama Cloud API-sleutel in bij Instellingen.", "Vul je Anthropic API-sleutel in bij Instellingen.",
  "Transcriptiemodel ontbreekt. Download het gekozen model bij Instellingen → Verwerking en verwerk daarna deze opname opnieuw. De opname wordt niet gewijzigd.",
  "Geen bruikbare spraak herkend. Controleer de opname en probeer opnieuw."])("excludes expected notice before replacing the UI message: %s", message => {
  const state = add();
  state.updateBackgroundTask("t", { status: "failed", error_message: message });
  expect(reportFailure).not.toHaveBeenCalled();
  expect(useRecordingStore.getState().backgroundTasks[0].error_message).toBe(message);
});
it("does not report stale unknown tasks, progress, cancellation status or same-status updates", () => {
  const state = add();
  state.updateBackgroundTask("missing", { status: "failed" });
  state.updateBackgroundTask("t", { status: "transcribing", progress: 5 });
  state.updateBackgroundTask("t", { progress: 10 });
  state.updateBackgroundTask("t", { status: "cancelled" });
  expect(reportFailure).not.toHaveBeenCalled();
});
it("retains the original C7 cancellation and cross-terminal rule", () => {
  expect(failureFromTransition("generating", "failed", "Geannuleerd door gebruiker.")).toBeNull();
  expect(failureFromTransition("failed", "error", "PRIVATE")).toBeNull();
});

it.each(["Provider: Vul je OpenAI API-sleutel in bij Instellingen.", "Geannuleerd door gebruiker. PRIVATE", "PRIVATE {\"provider\":\"unavailable\"}"])("reports untrusted/near-match text using fixed metadata: %s", error_message => {
  const state = add(); state.updateBackgroundTask("t", { status: "failed", error_message });
  expect(reportFailure).toHaveBeenCalledExactlyOnceWith("transcriberen", "Verwerking mislukt", "background_task_failed");
  expect(useRecordingStore.getState().backgroundTasks[0].error_message).toBe(error_message);
});
