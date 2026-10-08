import { expect, it, vi } from "vitest";
import { DEFAULT_SETTINGS } from "../../types";
import { isLocalEndpoint, localSettings, useSettingsStore } from "../settingsStore";
import { useAuthStore } from "../authStore";
import { useCalendarStore } from "../calendarStore";

it("migrates cloud settings without dropping local model choices", () => {
  const settings = localSettings({ ...DEFAULT_SETTINGS, processing_mode: "cloud", notulen_provider: "cloud", whisper_model: "small", ollama_model: "my-local-model", ollama_url: "https://ollama.com", ollama_api_key: "old-key" });
  expect(settings).toMatchObject({ processing_mode: "local", notulen_provider: "ollama-cloud", whisper_model: "small", ollama_model: "my-local-model", ollama_url: "https://ollama.com", ollama_api_key: "old-key", check_for_updates: false });
  useSettingsStore.getState().updateSettings({ processing_mode: "cloud", notulen_provider: "cloud", check_for_updates: true });
  expect(useSettingsStore.getState()).toMatchObject({ processing_mode: "local", notulen_provider: "ollama", check_for_updates: true });
});

it("rehydrates old desktop accounts without restoring app login while preserving calendar access", async () => {
  const load = vi.spyOn(useAuthStore.getState(), "loadTokenFromKeyring");
  localStorage.setItem("auth-store", JSON.stringify({ state: { isAuthenticated: true, user: { role: "admin" }, rememberMe: true }, version: 0 }));
  localStorage.setItem("calendar-store", JSON.stringify({ state: { isConnected: true, refreshToken: "old-token" }, version: 0 }));
  await useAuthStore.persist.rehydrate();
  await useCalendarStore.persist.rehydrate();
  expect(useAuthStore.getState().isAuthenticated).toBe(false);
  expect(useAuthStore.getState().isInitializing).toBe(false);
  expect(useCalendarStore.getState().isConnected).toBe(true);
  expect(load).not.toHaveBeenCalled();
});

it("accepts loopback endpoints and rejects remote or credentialed URLs", () => {
  for (const url of ["http://localhost:11434", "https://127.0.0.1:27124", "http://[::1]:1234"]) expect(isLocalEndpoint(url)).toBe(true);
  for (const url of ["https://ollama.com", "http://localhost.evil.test", "file:///tmp/data", "http://user:secret@localhost", "invalid"]) expect(isLocalEndpoint(url)).toBe(false);
});
