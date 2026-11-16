import { modelChoices, modelLabel, type ModelProvider } from "../../services/suggestedModels";

/** Model picker for providers billed per token: only suggested models within the price cap. */
export function CappedModelSelect({ provider, value, label, onChange }: {
  provider: ModelProvider; value: string; label: string; onChange: (model: string) => void;
}) {
  const choices = modelChoices(provider, value);
  return <>
    <select className="select" aria-label={label} style={{ width: "100%" }} value={choices.includes(value) ? value : ""}
      onChange={(e) => onChange(e.target.value)}>
      {!choices.includes(value) && <option value="" disabled>{value || "Kies een model"} (boven de prijsgrens)</option>}
      {choices.map(model => <option key={model} value={model}>{modelLabel(model)}</option>)}
    </select>
    <p className="settings-desc">Aanbevolen modellen tot $3 per miljoen invoertokens en $15 per miljoen uitvoertokens. Duurdere modellen zijn niet te kiezen.</p>
  </>;
}
