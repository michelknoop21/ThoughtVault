import { create } from "zustand";
import { persist } from "zustand/middleware";
import type { PersonProfile } from "../types";
import { usePersonProfileStore } from "./personProfileStore";

interface PeopleDirectoryState {
  people: PersonProfile[];  // isSelf: false entries only

  addPerson: (person: PersonProfile) => void;
  updatePerson: (id: string, partial: Partial<Omit<PersonProfile, "id" | "isSelf" | "createdAt">>) => void;
  removePerson: (id: string) => void;

  // Factory: returns a new PersonProfile with D-09 defaults (isSelf:false, isInternal:null, emails:[])
  createDefaultPerson: (overrides?: Partial<Omit<PersonProfile, "id" | "isSelf" | "createdAt" | "updatedAt">>) => PersonProfile;

  // Dedup helper: filters emails already in people[].emails and the selfEmail (case-insensitive, D-10)
  newSeedCandidates: (attendeeEmails: string[], selfEmail?: string) => string[];
}

export const usePeopleDirectoryStore = create<PeopleDirectoryState>()(
  persist(
    (set, get) => ({
      people: [],

      addPerson: (person) =>
        set((state) => ({
          // Invariant: isSelf must always be false in this store
          people: [...state.people, { ...person, isSelf: false }],
        })),

      updatePerson: (id, partial) =>
        set((state) => ({
          people: state.people.map((p) =>
            p.id === id
              ? { ...p, ...partial, updatedAt: new Date().toISOString() }
              : p
          ),
        })),

      removePerson: (id) =>
        set((state) => ({
          people: state.people.filter((p) => p.id !== id),
        })),

      createDefaultPerson: (overrides = {}) => ({
        id: crypto.randomUUID(),
        isSelf: false,
        isInternal: null,   // onbekend (D-09)
        emails: [],
        name: "",
        role: "",
        organization: "",
        aliases: [],
        meetingTypes: [],
        expertiseTags: [],
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString(),
        ...overrides,
      }),

      newSeedCandidates: (attendeeEmails, selfEmail) => {
        const { people } = get();
        const selfProfile = usePersonProfileStore.getState().profile;

        // Collect all known emails (case-insensitive)
        const knownEmails = new Set<string>();
        for (const person of people) {
          for (const email of person.emails) {
            knownEmails.add(email.toLowerCase());
          }
        }
        // Add self-profile emails (D-10 parity with macOS)
        for (const email of selfProfile?.emails ?? []) {
          knownEmails.add(email.toLowerCase());
        }
        if (selfEmail) {
          knownEmails.add(selfEmail.toLowerCase());
        }

        // Return only emails not already known
        return attendeeEmails.filter(
          (email) => !knownEmails.has(email.toLowerCase())
        );
      },
    }),
    {
      // MUST be distinct from "person-profile-store" / "profiles-store" / "settings-store" (Pitfall 4)
      name: "people-directory-store",
    }
  )
);
