import { describe, expect, it } from "vitest";
import { extractTitle, truncateTitle } from "../titleExtractor";

const body = "<p>Het team koos voor een nieuwe hostingpartij omdat de huidige te traag is.</p>";

describe("extractTitle", () => {
  it("skips a heading made only of genre words", () => {
    for (const h1 of ["Verslag meeting", "Verslaggesprek", "Gespreksverslag van het overleg", "Prompt", "Prompts", "Verslag van de meeting 10 november"]) {
      expect(extractTitle(`<h1>${h1}</h1>${body}`)).toBe("Het team koos voor een nieuwe hostingpartij omdat de huidige te traag is");
    }
  });

  it("does not promote a section heading when the h1 is rejected", () => {
    expect(extractTitle(`<h1>Notulen</h1><h2>Acties</h2>${body}`)).toBe("Het team koos voor een nieuwe hostingpartij omdat de huidige te traag is");
  });

  it("keeps a heading that names the purpose", () => {
    expect(extractTitle(`<h1>Keuze hostingpartij webshop</h1>${body}`)).toBe("Keuze hostingpartij webshop");
    expect(extractTitle(`<h1>Verslag hostingkeuze</h1>${body}`)).toBe("Verslag hostingkeuze");
  });

  it("cuts a long title at the last space", () => {
    const long = "Afspraken over Confluence-documentatie bij leverancierbeoordeling en contactmeldingen";
    expect(extractTitle(`<h1>${long}</h1>${body}`)).toBe("Afspraken over Confluence-documentatie bij leverancierbeoordeling en");
    expect(truncateTitle("a".repeat(60) + " planning, " + "b".repeat(30))).toBe("a".repeat(60) + " planning");
    expect(truncateTitle("x".repeat(100))).toBe("x".repeat(80));
  });
});
