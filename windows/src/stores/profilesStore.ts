import { create } from "zustand";
import { persist } from "zustand/middleware";
import type { Profile } from "../types";
import { DEFAULT_PROFILES } from "../types";

const legacyIds = new Set(["zakelijk", "informeel", "technisch", "handleiding", "blog_samenvatting", "notitie"]);

export function currentProfileChoices(remote: Profile[], prospectFlowEnabled = false): Profile[] {
  const builtInIds = new Set(DEFAULT_PROFILES.map((profile) => profile.id));
  return [
    ...DEFAULT_PROFILES.filter(p => p.id !== "prospectflow_offerte" || prospectFlowEnabled),
    ...remote.filter((profile) => !builtInIds.has(profile.id) && !legacyIds.has(profile.id) && !profile.is_default && !profile.isDefault),
  ];
}

interface ProfilesState {
  prospectFlowEnabled: boolean;
  setProspectFlowEnabled: (enabled: boolean) => void;
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
      prospectFlowEnabled: false,
      setProspectFlowEnabled: (enabled) => set(state => ({ prospectFlowEnabled: enabled, profiles: currentProfileChoices(state.profiles, enabled) })),
      profiles: currentProfileChoices([]),
      localProfiles: [],
      setProfiles: (profiles) => set(state => ({ profiles: currentProfileChoices(profiles, state.prospectFlowEnabled) })),
      showLocalProfiles: () => set((state) => ({ profiles: currentProfileChoices(state.localProfiles, state.prospectFlowEnabled) })),
      saveLocalProfile: (profile) => set((state) => {
        const localProfiles = [...state.localProfiles.filter((p) => p.id !== profile.id), profile];
        return { localProfiles, profiles: currentProfileChoices(localProfiles, get().prospectFlowEnabled) };
      }),
      deleteLocalProfile: (id) => set((state) => {
        const localProfiles = state.localProfiles.filter((p) => p.id !== id);
        return { localProfiles, profiles: currentProfileChoices(localProfiles, get().prospectFlowEnabled) };
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
          prospectFlowEnabled: false,
          localProfiles: saved?.localProfiles ?? [],
          profiles: currentProfileChoices(saved?.profiles ?? []),
        };
      },
    }
  )
);
