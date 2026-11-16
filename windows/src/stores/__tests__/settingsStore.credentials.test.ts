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
  expect(migrated).toEqual({ processing_mode: "local", notulen_provider: "ollama" });
});

it("removes plaintext credentials even when keyring migration fails", async () => {
  storeCredential.mockRejectedValue(new Error("keyring unavailable"));
  const migrated = await migrateLegacySettings({ ollama_api_key: "secret" });
  expect(migrated).not.toHaveProperty("ollama_api_key");
});

it("keeps the Ollama provider of installs from before OpenRouter and any explicit choice", async () => {
  expect(await migrateLegacySettings({ processing_mode: "local" })).toMatchObject({ notulen_provider: "ollama" });
  expect(await migrateLegacySettings({ notulen_provider: "lm-studio" })).toMatchObject({ notulen_provider: "lm-studio" });
});

it("defaults a fresh install to OpenRouter", async () => {
  const { DEFAULT_SETTINGS } = await import("../../types");
  expect(DEFAULT_SETTINGS.notulen_provider).toBe("openrouter");
  expect(DEFAULT_SETTINGS.openrouter_model).toBe("mistralai/mistral-large-4-0");
});

it("keeps existing values on migration and a stored install gets an empty usage ledger", async () => {
  const migrated = await migrateLegacySettings({ processing_mode: "local", notulen_provider: "openai", openai_model: "x", usage_ledger: { "2026-11": { notules: 2, requests: 9, cost_usd: 1, unknown_cost_runs: 0 } } });
  expect(migrated).toMatchObject({ notulen_provider: "openai", openai_model: "x", usage_ledger: { "2026-11": { notules: 2 } } });
  const { DEFAULT_SETTINGS } = await import("../../types");
  expect(DEFAULT_SETTINGS.usage_ledger).toEqual({});
});
