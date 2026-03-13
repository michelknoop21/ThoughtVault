import { create } from "zustand";
import { persist } from "zustand/middleware";
import type { AppSettings } from "../types";
import { DEFAULT_SETTINGS } from "../types";

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
    }
  )
);
