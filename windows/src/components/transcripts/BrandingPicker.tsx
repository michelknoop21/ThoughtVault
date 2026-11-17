import { useNavigate } from "react-router-dom";
import { useEffect, useState } from "react";
import {
  parseBranding,
  standardBranding,
} from "../../../../shared/document/dist/document.mjs";
import { useBrandingStore } from "../../stores/brandingStore";
import {
  useLocalTranscriptsStore,
  isLocalId,
} from "../../stores/localTranscriptsStore";
import { useTranscriptsStore } from "../../stores/transcriptsStore";
import type { Transcript } from "../../types";
export function BrandingPicker({ transcript }: { transcript: Transcript }) {
  const navigate = useNavigate();
  const { library, hydrate } = useBrandingStore();
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  useEffect(() => {
    void hydrate().catch((e) => setError(String(e)));
  }, [hydrate]);
  let applied;
  let parseError = "";
  try {
    applied = transcript.document_branding_json
      ? parseBranding(transcript.document_branding_json)
      : null;
  } catch {
    parseError = "De toegepaste huisstijl kan niet worden gelezen.";
  }
  async function apply(id: string) {
    setBusy(true);
    setError("");
    try {
      if (!isLocalId(transcript.id))
        throw Error(
          "Bewaar deze notule eerst lokaal om een huisstijl toe te passen.",
        );
      const style = library.styles.find((b) => b.id === id);
      const patch = {
        document_branding_json: JSON.stringify(style ?? standardBranding()),
      };
      await useLocalTranscriptsStore.getState().update(transcript.id, patch);
      useTranscriptsStore.getState().updateTranscript(transcript.id, patch);
    } catch (e) {
      setError(String(e));
    } finally {
      setBusy(false);
    }
  }
  return (
    <div
      style={{
        display: "flex",
        gap: 8,
        flexWrap: "wrap",
        alignItems: "center",
        padding: 12,
      }}
    >
      <label>
        Huisstijl{" "}
        <select
          aria-label="Huisstijl"
          disabled={busy}
          value={
            applied?.id === "thoughtvault" ? "" : (applied?.id ?? "legacy")
          }
          onChange={(e) => void apply(e.target.value)}
        >
          {!applied && (
            <option value="legacy" disabled>
              Huidige weergave behouden
            </option>
          )}
          <option value="">Standaard ThoughtVault</option>
          {applied &&
            applied.id !== "thoughtvault" &&
            !library.styles.some((b) => b.id === applied.id) && (
              <option value={applied.id}>
                {applied.name} (bewaarde versie)
              </option>
            )}
          {library.styles.map((b) => (
            <option key={b.id} value={b.id}>
              {b.name}
            </option>
          ))}
        </select>
      </label>
      {applied && <span>Versie {applied.revision}</span>}
      {applied && library.styles.some((b) => b.id === applied.id) && (
        <button
          className="btn btn-secondary btn-sm"
          disabled={busy}
          onClick={() => void apply(applied!.id)}
        >
          Nieuwste versie toepassen
        </button>
      )}
      <button
        className="btn btn-secondary btn-sm"
        onClick={() => navigate("/settings?tab=huisstijlen")}
      >
        Huisstijlen beheren
      </button>
      {(error || parseError) && <span role="alert">{error || parseError}</span>}
    </div>
  );
}
