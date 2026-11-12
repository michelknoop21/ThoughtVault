import { describe, expect, it } from "vitest";
import { extractTitle } from "../titleExtractor";

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
});
