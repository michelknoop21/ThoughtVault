import { beforeEach, expect, it, vi } from "vitest";
import { saveTextExport } from "../textExport";

const { save, writeTextFile } = vi.hoisted(() => ({ save: vi.fn(), writeTextFile: vi.fn() }));
vi.mock("@tauri-apps/plugin-dialog", () => ({ save }));
vi.mock("@tauri-apps/plugin-fs", () => ({ writeTextFile }));
beforeEach(() => vi.resetAllMocks());

it.each(["txt", "md", "html"] as const)("writes %s content to the selected native path before reporting success", async extension => {
  save.mockResolvedValue(`C:/exports/gekozen.${extension}`);
  let finish!: () => void;
  writeTextFile.mockImplementation(() => new Promise<void>(resolve => { finish = resolve; }));
  let completed = false;
  const result = saveTextExport("Iris: € 12.450 — geen verhoging", "Overleg", extension).then(saved => { completed = true; return saved; });
  await vi.waitFor(() => expect(writeTextFile).toHaveBeenCalledWith(`C:/exports/gekozen.${extension}`, "Iris: € 12.450 — geen verhoging"));
  expect(completed).toBe(false);
  finish();
  expect(await result).toBe(true);
  expect(save).toHaveBeenCalledWith(expect.objectContaining({ defaultPath: `Overleg.${extension}`, filters: [{ name: extension.toUpperCase(), extensions: [extension] }] }));
});

it("cancels without writing a file", async () => {
  save.mockResolvedValue(null);
  expect(await saveTextExport("Notulen", "Overleg", "txt")).toBe(false);
  expect(writeTextFile).not.toHaveBeenCalled();
});

it("surfaces a failed write instead of reporting a saved export", async () => {
  save.mockResolvedValue("C:/exports/overleg.md");
  writeTextFile.mockRejectedValue(new Error("Schijf vol"));
  await expect(saveTextExport("Notulen", "Overleg", "md")).rejects.toThrow("Schijf vol");
});
