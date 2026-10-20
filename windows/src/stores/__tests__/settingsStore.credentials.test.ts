import { expect, it, vi } from "vitest";
import { migrateLegacySettings } from "../settingsStore";

const { storeCredential } = vi.hoisted(() => ({ storeCredential: vi.fn() }));
vi.mock("../../services/tauriCommands", () => ({ storeCredential }));

it("moves existing provider and Obsidian keys into keyring before removing plaintext", async () => {
  storeCredential.mockResolvedValue(undefined);
  const migrated = await migrateLegacySettings({
    processing_mode: "local",
    ollama_api_key: "ollama-secret",
    obsidian_api_key: "obsidian-secret",
  });

  expect(storeCredential).toHaveBeenCalledWith("ollama_api_key", "ollama-secret");
  expect(storeCredential).toHaveBeenCalledWith("obsidian_api_key", "obsidian-secret");
  expect(migrated).toEqual({ processing_mode: "local" });
});

it("removes plaintext credentials even when keyring migration fails", async () => {
  storeCredential.mockRejectedValue(new Error("keyring unavailable"));
  const migrated = await migrateLegacySettings({ ollama_api_key: "secret" });
  expect(migrated).not.toHaveProperty("ollama_api_key");
});
