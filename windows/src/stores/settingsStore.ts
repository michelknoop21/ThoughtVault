import { storeCredential } from "../services/tauriCommands";
import { create } from "zustand";
import { persist } from "zustand/middleware";
import type { AppSettings } from "../types";
import { DEFAULT_SETTINGS } from "../types";

export function isLocalEndpoint(value: string): boolean {
  try {
    const url = new URL(value);
    return ["http:", "https:"].includes(url.protocol) &&
      ["localhost", "127.0.0.1", "[::1]"].includes(url.hostname) && !url.username && !url.password;
  } catch { return false; }
}

export function localSettings(settings: Partial<AppSettings>): AppSettings {
  return {
    ...DEFAULT_SETTINGS, ...settings,
    processing_mode: "local",
    notulen_provider: settings.notulen_provider === "cloud" ? (/^https:\/\/ollama\.com(?:\/|$)/i.test(settings.ollama_url ?? "") ? "ollama-cloud" : "ollama") : settings.notulen_provider ?? "ollama",
  };
}

interface SettingsState extends AppSettings {
  updateSettings: (settings: Partial<AppSettings>) => void;
  setHasCompletedOnboarding: (value: boolean) => void;
}

export const useSettingsStore = create<SettingsState>()(
  persist(
    (set) => ({
      ...DEFAULT_SETTINGS,
      updateSettings: (settings) => set((state) => localSettings({ ...state, ...settings })),
      setHasCompletedOnboarding: (value) =>
        set({ has_completed_onboarding: value }),
    }),
    {
      name: "settings-store",
      version: 2,
      migrate: async (saved) => {
        const previous = saved as Partial<AppSettings>;
        const settings = localSettings(previous);
        if (/^https:\/\/ollama\.com(?:\/|$)/i.test(settings.ollama_url) && ["ollama", "ollama-cloud"].includes(settings.notulen_provider)) {
          settings.notulen_provider = "ollama-cloud";
          settings.ollama_cloud_model = previous.ollama_cloud_model || previous.ollama_model || "";
        }
        if (settings.ollama_api_key) {
          await storeCredential("ollamaApiKey", settings.ollama_api_key);
          settings.ollama_api_key = "";
        }
        return settings;
      },
      partialize: (state) => ({ ...state, ollama_api_key: "" }),
      merge: (saved, current) => ({ ...current, ...localSettings(saved as Partial<AppSettings>) }),
    }
  )
);
