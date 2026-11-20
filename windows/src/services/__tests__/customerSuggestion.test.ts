import { expect, it, vi } from "vitest";
import { customerSources, meetingContext, parseCustomerSuggestion } from "../customerSuggestion";
import { useProfilesStore, currentProfileChoices } from "../../stores/profilesStore";
vi.mock("../llm", () => ({ LLMService: { complete: vi.fn() } }));
const sources = customerSources("Offerte voor Friese Installatietechniek", "Sanne is contactpersoon bij Friese Installatietechniek.", "", "");
it("accepts only a name grounded in a quote from the named source", () => {
  const raw = JSON.stringify({ name: "Friese Installatietechniek", source: "notes", quote: "Sanne is contactpersoon bij Friese Installatietechniek." });
  expect(parseCustomerSuggestion(raw, sources)?.name).toBe("Friese Installatietechniek");
  expect(parseCustomerSuggestion(raw.replace("Friese Installatietechniek", "Verzonnen BV"), sources)).toBeNull();
  expect(parseCustomerSuggestion(raw.replace('"notes"', '"meeting"'), sources)).toBeNull();
  expect(parseCustomerSuggestion("{}", sources)).toBeNull();
  expect(parseCustomerSuggestion("not JSON", sources)).toBeNull();
  expect(parseCustomerSuggestion('<think>{ reasoning }</think>```json\n' + raw + '\n```', sources)?.source).toBe("notes");
});
it("bounds excerpts and rejects prototype keys", () => {
  expect(customerSources("", "x".repeat(20000), "y".repeat(50000), "").notes).toHaveLength(16000);
  expect(parseCustomerSuggestion('{"name":"toString","source":"toString","quote":"toString"}', sources)).toBeNull();
});
it("uses only a unique appointment overlapping the recording date", () => {
  const event = { id: "1", title: "Offerte Friese Installatietechniek", start: "2026-11-17T09:00:00Z", end: "2026-11-17T10:00:00Z" };
  expect(meetingContext("2026-11-17T09:30:00Z", [event])).toBe(event.title);
  expect(meetingContext("2026-11-16T09:30:00Z", [event])).toBe("");
  expect(meetingContext("2026-11-17T09:30:00Z", [event, { ...event, id: "2" }])).toBe("");
});
it("keeps the offer profile hidden until the key is verified", () => {
  expect(currentProfileChoices([]).some(p => p.id === "prospectflow_offerte")).toBe(false);
  useProfilesStore.getState().setProspectFlowEnabled(true);
  expect(useProfilesStore.getState().profiles.some(p => p.id === "prospectflow_offerte")).toBe(true);
  useProfilesStore.getState().showLocalProfiles();
  expect(useProfilesStore.getState().profiles.some(p => p.id === "prospectflow_offerte")).toBe(true);
  useProfilesStore.getState().setProspectFlowEnabled(false);
  expect(useProfilesStore.getState().profiles.some(p => p.id === "prospectflow_offerte")).toBe(false);
});
