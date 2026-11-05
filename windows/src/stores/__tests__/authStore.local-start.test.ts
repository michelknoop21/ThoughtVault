import { expect, it, vi } from "vitest";
import { useAuthStore } from "../authStore";
import { useSettingsStore } from "../settingsStore";
import { DEFAULT_SETTINGS } from "../../types";

vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn(async () => null) }));

it("opens locally without credentials, including a saved cloud preference", async () => {
  expect(DEFAULT_SETTINGS.processing_mode).toBe("local");
  useAuthStore.setState({ isAuthenticated: false, token: null });
  useSettingsStore.getState().updateSettings({ processing_mode: "cloud" });
  await useAuthStore.getState().loadTokenFromKeyring();
  expect(useSettingsStore.getState().processing_mode).toBe("local");
  expect(useAuthStore.getState().isInitializing).toBe(false);
  expect(useAuthStore.getState().isAuthenticated).toBe(false);
});
