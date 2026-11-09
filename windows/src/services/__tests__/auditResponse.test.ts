import { expect, it } from "vitest";
import { auditNotule, auditSource } from "../notuleAudit";
const positive = { uncertain: false, source: [{ id: "T1", status: "covered" }], notes: [{ id: "N1", status: "supported", evidence: ["T1"] }] };
const fenced = (value: unknown) => "```json\n" + JSON.stringify(value) + "\n```";

it("accepts a complete indexed audit wrapped in one JSON code block", async () => {
  await expect(auditNotule("Noor belt vrijdag.", "<p>Noor neemt vrijdag telefonisch contact op.</p>", "", async () => fenced(positive))).resolves.toBeUndefined();
});
it("accepts a clear source check wrapped in one JSON code block", async () => {
  await expect(auditSource("Noor belt vrijdag.", "", async () => fenced({ uncertain: false }))).resolves.toBeUndefined();
});
it("keeps a fenced negative audit as a specific rejection", async () => {
  const missing = { ...positive, source: [...positive.source, { id: "T2", status: "missing" }] };
  await expect(auditNotule("Noor belt vrijdag. Bram controleert maandag.", "<p>Noor neemt vrijdag telefonisch contact op.</p>", "", async () => fenced(missing))).rejects.toThrow("De notule mist broninformatie: Bram controleert maandag.");
  await expect(auditSource("Onduidelijke bron.", "", async () => fenced({ uncertain: true }))).rejects.toThrow("De bron is onvoldoende duidelijk");
});
it.each([
  "Toelichting\n" + fenced(positive),
  fenced(positive) + "\nAkkoord",
  fenced(positive).replace("```json", "```html"),
  fenced(positive) + "\n" + fenced(positive),
  "```json\n{\"uncertain\":false,\n```",
])("does not extract approval from prose, another language, or malformed JSON", async response => {
  await expect(auditNotule("Noor belt vrijdag.", "<p>Noor neemt vrijdag telefonisch contact op.</p>", "", async () => response)).rejects.toThrow("geen bruikbaar controlebewijs");
});
