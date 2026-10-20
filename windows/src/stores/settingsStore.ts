import { create } from "zustand";
import { persist } from "zustand/middleware";
import type { AppSettings } from "../types";
import { DEFAULT_SETTINGS } from "../types";
import { storeCredential } from "../services/tauriCommands";

export async function migrateLegacySettings(value: unknown): Promise<Record<string, unknown>> {
  const state = { ...(value as Record<string, unknown>) };
  for (const key of ["ollama_api_key", "obsidian_api_key"]) {
    const secret = state[key];
    if (typeof secret === "string" && secret) {
      try { await storeCredential(key, secret); }
      catch { console.warn(`Sleutel ${key} kon niet naar de Windows-kluis worden verplaatst; voer deze opnieuw in.`); }
    }
    delete state[key];
  }
  return state;
}

interface SettingsState extends AppSettings {
  updateSettings: (settings: Partial<AppSettings>) => void;
  setHasCompletedOnboarding: (value: boolean) => void;
}

export const useSettingsStore = create<SettingsState>()(
  persist(
    (set) => ({
      ...DEFAULT_SETTINGS,
      updateSettings: (settings) => set((state) => ({ ...state, ...settings })),
      setHasCompletedOnboarding: (value) =>
        set({ has_completed_onboarding: value }),
    }),
    {
      name: "settings-store",
      version: 1,
      migrate: migrateLegacySettings,
    }
  )
);
