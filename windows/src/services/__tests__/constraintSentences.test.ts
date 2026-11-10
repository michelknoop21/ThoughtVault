import { expect, it } from "vitest";
import { constraintSentences } from "../notuleAudit";

// Same cases as ThoughtVaultTests/NotuleConstraintTests.swift.
it("keeps the ASCII keyword boundary", () => {
  expect(constraintSentences("éniet doen. Dat is nietig. Er is een OPEN VRAAG. NIET doen. Niet doen.")).toEqual(
    ["éniet doen.", "Er is een OPEN VRAAG.", "NIET doen.", "Niet doen."]);
});

it("does not make a hedged or questioning negation mandatory", () => {
  expect(constraintSentences("Ik denk niet dat het dat is. Misschien zit het niet bij de regenpijp. Is dat niet raar? Nee, dat weet ik niet. Waarschijnlijk niet.")).toEqual([]);
});

it("keeps every unhedged negation mandatory, also with pronouns, and anchored hedged ones", () => {
  const kept = ["We delen geen klantgegevens met derden.", "We starten niet zonder handtekening van de klant.", "Dus de afspraak van vrijdag gaat niet door.", "We betalen geen duizend euro.", "De API kan niet zonder authenticatie worden gebruikt.", "Het budget is 12.450 euro inclusief btw, niet 15.000 euro.", "We mogen geen klantgegevens doorsturen.",
    "Ik mag alleen de gevolgschade noteren, dat zit er niet in.", "Er is nog geen leverancier gekozen.",
    "Bram is afwezig, dus ik weet het niet.", "We besluiten dit niet vandaag.", "Is de migratie op 16 november niet doorgegaan?",
    "De bibliotheek is tijdens de interne proef niet toegankelijk voor bezoekers."];
  expect(constraintSentences(kept.join(" "))).toEqual(kept);
});

it("keeps duplicates out and only trims", () => {
  expect(constraintSentences("Geen  budget.\nGeen  budget. Wel tijd.")).toEqual(["Geen  budget."]);
});
