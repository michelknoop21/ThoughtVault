import { expect, it } from "vitest";
import { constraintSentences } from "../notuleAudit";

// Same cases as ThoughtVaultTests/NotuleConstraintTests.swift.
it("keeps the ASCII keyword boundary", () => {
  expect(constraintSentences("éniet doen. Dat is nietig. Er is een OPEN VRAAG. NIET doen. Niet doen.")).toEqual(
    ["éniet doen.", "Er is een OPEN VRAAG.", "NIET doen.", "Niet doen."]);
});

it("does not make spoken filler with a negation mandatory", () => {
  expect(constraintSentences("Ik denk niet dat het dat is. Dus dat wordt nooit nat. Je kunt het niet zien, natuurlijk. Is dat niet raar? Nee, dat weet ik niet.")).toEqual([]);
});

it("keeps numbers, permissions, decisions, strong keywords and plain factual negations mandatory", () => {
  const kept = ["Het budget is 12.450 euro inclusief btw, niet 15.000 euro.", "We mogen geen klantgegevens doorsturen.",
    "Ik mag alleen de gevolgschade noteren, dat zit er niet in.", "Er is nog geen leverancier gekozen.",
    "Bram is afwezig, dus ik weet het niet.", "Is de migratie op 16 november niet doorgegaan?",
    "De bibliotheek is tijdens de interne proef niet toegankelijk voor bezoekers."];
  expect(constraintSentences(kept.join(" "))).toEqual(kept);
});

it("keeps duplicates out and only trims", () => {
  expect(constraintSentences("Geen  budget.\nGeen  budget. Wel tijd.")).toEqual(["Geen  budget."]);
});
