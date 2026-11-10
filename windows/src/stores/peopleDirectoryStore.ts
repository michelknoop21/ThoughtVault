import { create } from "zustand";
import { persist } from "zustand/middleware";
import type { PersonProfile } from "../types";
import { usePersonProfileStore } from "./personProfileStore";
import { applySnapshot, personSnapshot, recordChange, type HistoryEntry, type PersonSnapshot } from "../services/contextHistory";

type PersonChanges = Partial<Omit<PersonProfile, "id" | "isSelf" | "createdAt">>;

interface PeopleDirectoryState {
  people: PersonProfile[];  // isSelf: false entries only

  addPerson: (person: PersonProfile) => void;
  updatePerson: (id: string, partial: Partial<Omit<PersonProfile, "id" | "isSelf" | "createdAt">>) => void;
  removePerson: (id: string) => void;
  /**
   * Like updatePerson, but when anything changed the state from before is kept in ContextHistory under `source`.
   * A function receives the person as it is when the update runs, so merges see earlier updates.
   */
  recordUpdate: (id: string, source: string, partial: PersonChanges | ((person: PersonProfile) => PersonChanges)) => Promise<void>;
  /** Puts an earlier version back; the current state is recorded first, so nothing is lost. */
  restorePerson: (entry: HistoryEntry) => Promise<void>;

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

      // Before-state, history and update all run inside the history queue.
      recordUpdate: (id, source, partial) => recordChange("person", id, source, () => {
        const person = get().people.find((p) => p.id === id);
        if (!person) return undefined;
        const changes = typeof partial === "function" ? partial(person) : partial;
        const before = personSnapshot(person);
        const changed = JSON.stringify(personSnapshot({ ...person, ...changes })) !== JSON.stringify(before);
        return { before: changed ? before : undefined, apply: () => get().updatePerson(id, changes) };
      }),

      restorePerson: (entry) => {
        const snapshot = JSON.parse(entry.snapshotJSON) as PersonSnapshot;
        // id, isSelf and createdAt come back unchanged from the current person.
        return get().recordUpdate(entry.itemId, "herstel", (person): PersonChanges => applySnapshot(snapshot, person));
      },

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
        responsibilities: [],
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
      // v1 adds responsibilities; people saved before that get an empty list.
      version: 1,
      migrate: (persisted) => {
        const state = persisted as { people?: PersonProfile[] };
        return { ...state, people: (state.people ?? []).map((p) => ({ ...p, responsibilities: p.responsibilities ?? [] })) } as PeopleDirectoryState;
      },
    }
  )
);
