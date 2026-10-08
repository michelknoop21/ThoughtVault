import { create } from "zustand";
import { persist } from "zustand/middleware";
import type { Profile } from "../types";
import { DEFAULT_PROFILES } from "../types";

const legacyIds = new Set(["zakelijk", "informeel", "technisch", "handleiding", "blog_samenvatting", "notitie"]);

export function currentProfileChoices(remote: Profile[]): Profile[] {
  const builtInIds = new Set(DEFAULT_PROFILES.map((profile) => profile.id));
  return [
    ...DEFAULT_PROFILES,
    ...remote.filter((profile) => !builtInIds.has(profile.id) && !legacyIds.has(profile.id) && !profile.is_default && !profile.isDefault),
  ];
}

interface ProfilesState {
  profiles: Profile[];
  localProfiles: Profile[];
  setProfiles: (profiles: Profile[]) => void;
  showLocalProfiles: () => void;
  saveLocalProfile: (profile: Profile) => void;
  deleteLocalProfile: (id: string) => void;
  addProfile: (profile: Profile) => void;
  updateProfile: (id: string, updates: Partial<Profile>) => void;
  deleteProfile: (id: string) => void;
  getProfile: (id: string) => Profile | undefined;
}

export const useProfilesStore = create<ProfilesState>()(
  persist(
    (set, get) => ({
      profiles: DEFAULT_PROFILES,
      localProfiles: [],
      setProfiles: (profiles) => set({ profiles }),
      showLocalProfiles: () => set((state) => ({ profiles: currentProfileChoices(state.localProfiles) })),
      saveLocalProfile: (profile) => set((state) => {
        const localProfiles = [...state.localProfiles.filter((p) => p.id !== profile.id), profile];
        const profiles = currentProfileChoices(localProfiles);
        // Fail before publishing state when browser storage is unavailable/full.
        localStorage.setItem("profiles-store", JSON.stringify({ state: { ...state, localProfiles, profiles }, version: 0 }));
        return { localProfiles, profiles };
      }),
      deleteLocalProfile: (id) => set((state) => {
        const localProfiles = state.localProfiles.filter((p) => p.id !== id);
        return { localProfiles, profiles: currentProfileChoices(localProfiles) };
      }),
      addProfile: (profile) =>
        set((state) => ({ profiles: [...state.profiles, profile] })),
      updateProfile: (id, updates) =>
        set((state) => ({
          profiles: state.profiles.map((p) =>
            p.id === id ? { ...p, ...updates } : p
          ),
        })),
      deleteProfile: (id) =>
        set((state) => ({
          profiles: state.profiles.filter((p) => p.id !== id),
        })),
      getProfile: (id) => get().profiles.find((p) => p.id === id),
    }),
    {
      name: "profiles-store",
      merge: (persisted, current) => {
        const saved = persisted as Partial<ProfilesState> | undefined;
        return {
          ...current,
          ...persisted as object,
          localProfiles: saved?.localProfiles ?? [],
          profiles: currentProfileChoices(saved?.profiles ?? []),
        };
      },
    }
  )
);
