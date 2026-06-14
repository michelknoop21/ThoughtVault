import { usePeopleDirectoryStore } from "../stores/peopleDirectoryStore";
import { usePersonProfileStore } from "../stores/personProfileStore";

/**
 * A meeting participant sent to the notule pipeline so the LLM can render an
 * attendee list and attribute action points by name. Mirrors the macOS Participant
 * model and the backend's expected shape.
 */
export interface Participant {
  name: string;
  role: string;
  organization: string;
}

/** Derive a display name from an email local-part (john.doe@x → "John Doe"). */
export function deriveDisplayName(email: string): string {
  const prefix = email.split("@")[0] ?? email;
  return prefix
    .split(/[._-]/)
    .map((s) => (s ? s.charAt(0).toUpperCase() + s.slice(1) : s))
    .join(" ");
}

/**
 * Build the participant list for one recording: self-profile + calendar attendees
 * (resolved against the directory by email, else email-derived) + manually selected
 * directory people. Deduplicated by lowercased name; nameless entries dropped.
 */
export function resolveParticipants(
  attendeeEmails: string[],
  manualIds: string[],
  includeSelf: boolean = true,
): Participant[] {
  const people = usePeopleDirectoryStore.getState().people;
  const self = usePersonProfileStore.getState().profile;

  const result: Participant[] = [];
  const seen = new Set<string>();

  const pushRaw = (name: string, role = "", organization = "") => {
    const trimmed = name.trim();
    if (!trimmed) return;
    const key = trimmed.toLowerCase();
    if (seen.has(key)) return;
    seen.add(key);
    result.push({ name: trimmed, role: role.trim(), organization: organization.trim() });
  };

  // Self first so it heads the attendee list.
  if (includeSelf && self) {
    pushRaw(self.name, self.role, self.organization);
  }

  // Calendar attendees → directory match by email, else email-derived name.
  const byEmail = new Map<string, (typeof people)[number]>();
  for (const person of people) {
    for (const email of person.emails) {
      const k = email.toLowerCase();
      if (!byEmail.has(k)) byEmail.set(k, person);
    }
  }
  for (const email of attendeeEmails) {
    const match = byEmail.get(email.toLowerCase());
    if (match) pushRaw(match.name, match.role, match.organization);
    else pushRaw(deriveDisplayName(email));
  }

  // Manually selected directory people (ad-hoc meetings).
  const byId = new Map(people.map((p) => [p.id, p]));
  for (const id of manualIds) {
    const person = byId.get(id);
    if (person) pushRaw(person.name, person.role, person.organization);
  }

  return result;
}
