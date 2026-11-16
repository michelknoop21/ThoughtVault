import { beforeEach, expect, it, vi } from "vitest";
import { DEFAULT_SETTINGS, type Transcript } from "../../types";
import { buildObsidianNote, exportToObsidian, importFromObsidian, testObsidian, ObsidianBrokenError } from "../obsidian";
import { useObsidianLinkStore } from "../../stores/obsidianStore";

const { invoke, loadCredential } = vi.hoisted(() => ({ invoke: vi.fn(), loadCredential: vi.fn() }));
vi.mock("@tauri-apps/api/core", () => ({ invoke }));
vi.mock("../tauriCommands", () => ({ loadCredential }));
vi.mock("../appLog", () => ({ log: { info: vi.fn(), warn: vi.fn(), error: vi.fn() } }));
const ON = { ...DEFAULT_SETTINGS, obsidian_enabled: true };

const note: Transcript = {
  id: "local-123", title: "Overleg", notule_html: "<h1>Overleg</h1><p>Planning is akkoord.</p>",
  tags: [], duration_seconds: 10, created_at: "2026-09-30T10:00:00Z", updated_at: "2026-09-30T10:00:00Z",
};

beforeEach(() => {
  vi.resetAllMocks();
  localStorage.clear();
  useObsidianLinkStore.getState().setBroken(false);
  loadCredential.mockResolvedValue("obsidian-secret");
});

it("uses the immutable transcript ID for the vault filename", () => {
  expect(buildObsidianNote(note).filename).toContain("local-123");
  expect(buildObsidianNote({ ...note, title: "Nieuwe titel" }).filename).toBe(buildObsidianNote(note).filename);
});

it("does not overwrite an Obsidian edit during auto export", async () => {
  invoke.mockResolvedValueOnce({ status: 404, body: "" }).mockResolvedValueOnce({ status: 204, body: "" });
  await exportToObsidian(note, ON);
  invoke.mockClear();
  invoke.mockResolvedValue({ status: 200, body: "---\nthoughtvault_id: local-123\n---\n\n# Extern bewerkt" });

  await expect(exportToObsidian({ ...note, notule_html: "<p>App bewerkt</p>" }, ON))
    .rejects.toThrow("gewijzigd in Obsidian");
  expect(invoke).toHaveBeenCalledTimes(1);
});

it("exports changed metadata when the notule body stays the same", async () => {
  invoke.mockResolvedValueOnce({ status: 404, body: "" }).mockResolvedValueOnce({ status: 204, body: "" });
  await exportToObsidian(note, ON);
  invoke.mockClear();
  invoke.mockResolvedValueOnce({ status: 200, body: buildObsidianNote(note).markdown })
    .mockResolvedValueOnce({ status: 204, body: "" });
  const updated = { ...note, title: "Nieuwe titel", tags: ["planning"], profile_name: "Besluiten" };
  await exportToObsidian(updated, ON);
  expect(invoke).toHaveBeenCalledWith("obsidian_put", expect.objectContaining({
    markdown: buildObsidianNote(updated).markdown,
  }));
});

it("imports changed Markdown as safe editable HTML", async () => {
  invoke.mockResolvedValue({ status: 200, body: "---\nthoughtvault_id: local-123\n---\n\n# Extern bewerkt\n\nEen besluit." });
  const imported = await importFromObsidian(note, ON);
  expect(imported.html).toContain("<h1>Extern bewerkt</h1>");
  expect(imported.html).toContain("Een besluit.");
  expect(imported.markdown).toContain("# Extern bewerkt");
});

it("can import an older title-based Obsidian note", async () => {
  invoke.mockResolvedValueOnce({ status: 404, body: "" })
    .mockResolvedValueOnce({ status: 200, body: "# Bestaande notule" });
  const imported = await importFromObsidian(note, ON);
  expect(imported.html).toContain("Bestaande notule");
  expect(invoke.mock.calls[1][1].filename).toContain("overleg.md");
});

it("makes no Obsidian request for export or import when the switch is off", async () => {
  await exportToObsidian(note, DEFAULT_SETTINGS);
  await expect(importFromObsidian(note, DEFAULT_SETTINGS)).rejects.toThrow("staat uit");
  expect(invoke).not.toHaveBeenCalled();
  expect(loadCredential).not.toHaveBeenCalled();
});

it("marks the link broken on a failed connection and skips further calls", async () => {
  invoke.mockRejectedValue("connection refused");
  await expect(exportToObsidian(note, ON)).rejects.toBeInstanceOf(ObsidianBrokenError);
  expect(useObsidianLinkStore.getState().broken).toBe(true);
  invoke.mockClear();
  await expect(exportToObsidian(note, ON)).rejects.toBeInstanceOf(ObsidianBrokenError);
  await expect(importFromObsidian(note, ON)).rejects.toBeInstanceOf(ObsidianBrokenError);
  expect(invoke).not.toHaveBeenCalled();
});

it.each([401, 403])("marks the link broken on status %i", async (status) => {
  invoke.mockResolvedValue({ status, body: "" });
  await expect(exportToObsidian(note, ON)).rejects.toBeInstanceOf(ObsidianBrokenError);
  expect(useObsidianLinkStore.getState().broken).toBe(true);
});

it("keeps a plain error for a 404 on one note", async () => {
  invoke.mockResolvedValue({ status: 404, body: "" });
  await expect(importFromObsidian(note, ON)).rejects.toThrow("niet gevonden");
  expect(useObsidianLinkStore.getState().broken).toBe(false);
});

it("clears the broken state after a successful connection test", async () => {
  useObsidianLinkStore.getState().setBroken(true);
  invoke.mockResolvedValue({ status: 200, body: '{ "authenticated": true }' });
  await testObsidian(ON);
  expect(useObsidianLinkStore.getState().broken).toBe(false);
});

it("keeps the broken state when the connection test fails", async () => {
  invoke.mockRejectedValue("certificate error");
  await expect(testObsidian(ON)).rejects.toBe("certificate error");
  expect(useObsidianLinkStore.getState().broken).toBe(true);
});
