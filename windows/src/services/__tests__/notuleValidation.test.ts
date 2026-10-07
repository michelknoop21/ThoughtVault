import { describe, expect, it } from "vitest";
import { hasUsableTranscription, hasUsableNotule } from "../notuleValidation";

describe("completed note content", () => {
  it("rejects empty recognition and a placeholder transcript", () => {
    expect(hasUsableTranscription("... ")).toBe(false);
    expect(hasUsableTranscription("   ")).toBe(false);
    expect(hasUsableTranscription("Geen transcriptie.")).toBe(false);
    expect(hasUsableTranscription("[ruis] ... (stilte) ... [onverstaanbaar]")).toBe(false);
    expect(hasUsableTranscription("De planning voor volgende week is besproken.")).toBe(true);
  });

  it("rejects empty HTML, a copied template, and a missing-transcript response", () => {
    expect(hasUsableNotule("<style>h1{color:red}</style><div>...</div>")).toBe(false);
    expect(hasUsableNotule("<h1>[Beschrijvende titel]</h1><p>[Samenvatting]</p>")).toBe(false);
    expect(hasUsableNotule("<p>Er is geen transcriptie aangeleverd. Lever die eerst aan.</p>")).toBe(false);
    expect(hasUsableNotule("<h2>Kernuitkomst</h2><p>De planning voor volgende week is besproken.</p>")).toBe(true);
  });
});
