import { create } from "zustand";
import { persist } from "zustand/middleware";
import type { PersonProfile } from "../types";

interface PersonProfileState {
  profile: PersonProfile | null;
  upsertProfile: (
    updates: Partial<Omit<PersonProfile, "id" | "isSelf" | "createdAt">>
  ) => void;
  clearProfile: () => void;
}

export const usePersonProfileStore = create<PersonProfileState>()(
  persist(
    (set) => ({
      profile: null,
      upsertProfile: (updates) =>
        set((state) => ({
          profile: state.profile
            ? {
                ...state.profile,
                ...updates,
                updatedAt: new Date().toISOString(),
              }
            : {
                id: crypto.randomUUID(),
                isSelf: true,
                isInternal: true,
                name: "",
                role: "",
                organization: "",
                aliases: [],
                meetingTypes: [],
                expertiseTags: [],
                createdAt: new Date().toISOString(),
                updatedAt: new Date().toISOString(),
                ...updates,
              },
        })),
      clearProfile: () => set({ profile: null }),
    }),
    {
      // MUST differ from "profiles-store" and "settings-store" (Pitfall 4)
      name: "person-profile-store",
    }
  )
);
