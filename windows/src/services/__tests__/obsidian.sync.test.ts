import { beforeEach, expect, it, vi } from "vitest";
import { DEFAULT_SETTINGS, type Transcript } from "../../types";
import { buildObsidianNote, exportToObsidian, importFromObsidian } from "../obsidian";

const { invoke, loadCredential } = vi.hoisted(() => ({ invoke: vi.fn(), loadCredential: vi.fn() }));
vi.mock("@tauri-apps/api/core", () => ({ invoke }));
vi.mock("../tauriCommands", () => ({ loadCredential }));

const note: Transcript = {
  id: "local-123", title: "Overleg", notule_html: "<h1>Overleg</h1><p>Planning is akkoord.</p>",
  tags: [], duration_seconds: 10, created_at: "2026-09-30T10:00:00Z", updated_at: "2026-09-30T10:00:00Z",
};

beforeEach(() => {
  vi.resetAllMocks();
  localStorage.clear();
  loadCredential.mockResolvedValue("obsidian-secret");
});

it("uses the immutable transcript ID for the vault filename", () => {
  expect(buildObsidianNote(note).filename).toContain("local-123");
  expect(buildObsidianNote({ ...note, title: "Nieuwe titel" }).filename).toBe(buildObsidianNote(note).filename);
});

it("does not overwrite an Obsidian edit during auto export", async () => {
  invoke.mockResolvedValueOnce({ status: 404, body: "" }).mockResolvedValueOnce({ status: 204, body: "" });
  await exportToObsidian(note, DEFAULT_SETTINGS);
  invoke.mockClear();
  invoke.mockResolvedValue({ status: 200, body: "---\nthoughtvault_id: local-123\n---\n\n# Extern bewerkt" });

  await expect(exportToObsidian({ ...note, notule_html: "<p>App bewerkt</p>" }, DEFAULT_SETTINGS))
    .rejects.toThrow("gewijzigd in Obsidian");
  expect(invoke).toHaveBeenCalledTimes(1);
});

it("exports changed metadata when the notule body stays the same", async () => {
  invoke.mockResolvedValueOnce({ status: 404, body: "" }).mockResolvedValueOnce({ status: 204, body: "" });
  await exportToObsidian(note, DEFAULT_SETTINGS);
  invoke.mockClear();
  invoke.mockResolvedValueOnce({ status: 200, body: buildObsidianNote(note).markdown })
    .mockResolvedValueOnce({ status: 204, body: "" });
  const updated = { ...note, title: "Nieuwe titel", tags: ["planning"], profile_name: "Besluiten" };
  await exportToObsidian(updated, DEFAULT_SETTINGS);
  expect(invoke).toHaveBeenCalledWith("obsidian_put", expect.objectContaining({
    markdown: buildObsidianNote(updated).markdown,
  }));
});

it("imports changed Markdown as safe editable HTML", async () => {
  invoke.mockResolvedValue({ status: 200, body: "---\nthoughtvault_id: local-123\n---\n\n# Extern bewerkt\n\nEen besluit." });
  const imported = await importFromObsidian(note, DEFAULT_SETTINGS);
  expect(imported.html).toContain("<h1>Extern bewerkt</h1>");
  expect(imported.html).toContain("Een besluit.");
  expect(imported.markdown).toContain("# Extern bewerkt");
});

it("can import an older title-based Obsidian note", async () => {
  invoke.mockResolvedValueOnce({ status: 404, body: "" })
    .mockResolvedValueOnce({ status: 200, body: "# Bestaande notule" });
  const imported = await importFromObsidian(note, DEFAULT_SETTINGS);
  expect(imported.html).toContain("Bestaande notule");
  expect(invoke.mock.calls[1][1].filename).toContain("overleg.md");
});
