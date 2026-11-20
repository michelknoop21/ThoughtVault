import { act } from "react";
import { Store } from "@tauri-apps/plugin-store";
import { createRoot } from "react-dom/client";
import { afterEach, expect, it, vi } from "vitest";
import { TranscriptsPage } from "../TranscriptsPage";
import { useSettingsStore } from "../../stores/settingsStore";
import { useLocalTranscriptsStore } from "../../stores/localTranscriptsStore";
import { useTranscriptsStore } from "../../stores/transcriptsStore";
import { useProfilesStore } from "../../stores/profilesStore";
import { useRecordingStore } from "../../stores/recordingStore";
import { api } from "../../services/api";
import { LLMService } from "../../services/llm";
import { UsageMeter } from "../../services/usageMeter";
import type { Transcript } from "../../types";

afterEach(() => {
  vi.restoreAllMocks();
  useSettingsStore.getState().updateSettings({ processing_mode: "cloud", profile_detail_levels: {} });
  useLocalTranscriptsStore.setState({ items: [] });
  useTranscriptsStore.setState({ transcripts: [], selectedId: null });
  useRecordingStore.setState({ backgroundTasks: [] });
});

async function openDialog(note: Transcript) {
  vi.spyOn(api, "getTranscripts").mockResolvedValue(note.id.startsWith("local-") ? [] : [note]);
  useProfilesStore.setState({ profiles: [
    { id: "executive", name: "Executive" }, { id: "klantgesprek", name: "Klantgesprek" }, { id: "promptnotitie", name: "Promptnotitie" },
  ] });
  vi.spyOn(Store, "load").mockResolvedValue({ get: vi.fn().mockResolvedValue([]), set: vi.fn(), save: vi.fn() } as unknown as Store);
  await useLocalTranscriptsStore.getState().hydrate();
  if (note.id.startsWith("local-")) await useLocalTranscriptsStore.getState().add(note);
  useTranscriptsStore.setState({ transcripts: [note], selectedId: note.id });
  const container = document.createElement("div");
  const root = createRoot(container);
  await act(async () => { root.render(<TranscriptsPage />); });
  await act(async () => { container.querySelector<HTMLButtonElement>('button[title="Notulen opnieuw genereren met AI"]')!.click(); });
  const dialog = () => container.querySelector(".td-overlay")!;
  const pressed = () => dialog().querySelector('[aria-label="Detailniveau"] button[aria-pressed="true"]')?.textContent;
  const button = (label: string) => Array.from(dialog().querySelectorAll<HTMLButtonElement>("button")).find((b) => b.textContent === label)!;
  const choose = async (id: string) => {
    const select = dialog().querySelector<HTMLSelectElement>("select")!;
    await act(async () => { select.value = id; select.dispatchEvent(new Event("change", { bubbles: true })); });
  };
  return { root, dialog, pressed, button, choose };
}

const note = (id: string): Transcript => ({
  id, title: "Overleg", raw_transcription: "We hebben de planning goedgekeurd.", notule_html: "<p>Oud</p>",
  duration_seconds: 12, profile_name: "Oude profielnaam", profile_id: "executive", detail_level: "normaal", tags: [],
  created_at: new Date().toISOString(), updated_at: new Date().toISOString(),
});

it("preselects the level per profile and regenerates with the level the user picked", async () => {
  useSettingsStore.getState().updateSettings({ processing_mode: "local", profile_detail_levels: { klantgesprek: "volledig" } });
  const generate = vi.spyOn(LLMService, "generateNotulen").mockResolvedValue("<h1>Planning voor komend kwartaal</h1><p>De planning is door het team goedgekeurd.</p>");
  const { root, dialog, pressed, button, choose } = await openDialog(note("local-detail"));

  expect(pressed()).toBe("Normaal"); // same profile: the level stored on the notule, not executive's kort
  await choose("klantgesprek");
  expect(pressed()).toBe("Volledig"); // other profile: the user's choice for it
  await choose("promptnotitie");
  expect(dialog().querySelector('[aria-label="Detailniveau"]')).toBeNull();
  await choose("executive");
  expect(pressed()).toBe("Normaal");

  await act(async () => { button("Kort").click(); });
  await act(async () => { button("Regenereren").click(); });
  expect(generate).toHaveBeenCalledWith(expect.any(String), expect.objectContaining({ id: "executive" }), expect.any(Function), [], "",
    expect.any(Function), expect.any(UsageMeter), false, undefined, "kort");
  expect(useLocalTranscriptsStore.getState().items.find((item) => item.id === "local-detail")?.detail_level).toBe("kort");
  await act(async () => { root.unmount(); });
});

it("offers no level for a cloud transcript", async () => {
  const { root, dialog } = await openDialog(note("cloud-detail"));
  expect(dialog().querySelector("select")).not.toBeNull();
  expect(dialog().querySelector('[aria-label="Detailniveau"]')).toBeNull();
  await act(async () => { root.unmount(); });
});
