import type { Dispatch, SetStateAction } from "react";

export const STIJLEN = [
  {
    id: "zakelijk",
    label: "Zakelijk",
    description: "Formele toon, geschikt voor directie en management",
    system_prompt: "Je bent een professionele notulist die zakelijke vergaderingen nauwkeurig en beknopt samenvat.",
  },
  {
    id: "informeel",
    label: "Informeel",
    description: "Vlotte, leesbare toon voor team-overleggen",
    system_prompt: "Je bent een vriendelijke assistent die gesprekken in begrijpelijke taal samenvat.",
  },
  {
    id: "technisch",
    label: "Technisch",
    description: "Technisch jargon, focus op architectuur en code",
    system_prompt: "Je bent een technische notulist gespecialiseerd in software ontwikkeling en IT-projecten.",
  },
] as const;

export const DEFAULT_SYSTEM_PROMPT = STIJLEN[0].system_prompt;

// Empty form state for create modal
export const emptyForm = {
  name: "",
  description: "",
  icon: "",
  stijl: "zakelijk" as string,
  system_prompt: "",
  notule_prompt: "",
  notule_template: "",
  sections: "",
};

export function ProfileEditForm({ editing, form, setForm, loading, onClose, onSave }: {
  editing: boolean;
  form: typeof emptyForm;
  setForm: Dispatch<SetStateAction<typeof emptyForm>>;
  loading: boolean;
  onClose: () => void;
  onSave: () => void;
}) {
  return (
          <div className="card profile-modal">
            <p className="text-body-strong profile-modal-title">
              {editing ? "Profiel bewerken" : "Nieuw profiel"}
            </p>
            <div className="flex-col gap-10">
              <div className="form-field">
                <label className="form-label">Naam</label>
                <input
                  className="input"
                  value={form.name}
                  onChange={(e) => setForm({ ...form, name: e.target.value })}
                  placeholder="Bijv. Brainstorm, Standup, Klantgesprek"
                />
              </div>
              <div className="form-field">
                <label className="form-label">Beschrijving</label>
                <input
                  className="input"
                  value={form.description}
                  onChange={(e) => setForm({ ...form, description: e.target.value })}
                  placeholder="Korte omschrijving van dit profiel"
                />
              </div>
              <div className="form-field">
                <label className="form-label">Icoon (emoji)</label>
                <input
                  className="input"
                  value={form.icon}
                  onChange={(e) => setForm({ ...form, icon: e.target.value })}
                  placeholder="Bijv. 📝"
                  style={{ width: 80 }}
                />
              </div>
              <div className="form-field">
                <label className="form-label">Stijl</label>
                <div style={{ display: "flex", gap: 8 }}>
                  {STIJLEN.map((stijl) => (
                    <button
                      key={stijl.id}
                      type="button"
                      onClick={() => setForm({ ...form, stijl: stijl.id })}
                      className="card-static"
                      style={{
                        flex: 1,
                        display: "flex",
                        flexDirection: "column",
                        alignItems: "center",
                        justifyContent: "flex-start",
                        padding: "10px 8px",
                        textAlign: "center",
                        cursor: "pointer",
                        border: form.stijl === stijl.id ? "1.5px solid var(--fill-accent)" : "1px solid var(--stroke-default)",
                        background: form.stijl === stijl.id ? "var(--fill-accent-subtle)" : "var(--bg-card)",
                        borderRadius: 8,
                      }}
                    >
                      <p style={{ margin: 0, fontWeight: 600, fontSize: 13, color: form.stijl === stijl.id ? "var(--interactive-text)" : "var(--text-primary)" }}>
                        {stijl.label}
                      </p>
                      <p className="text-caption" style={{ margin: "4px 0 0", color: "var(--text-tertiary)" }}>
                        {stijl.description}
                      </p>
                    </button>
                  ))}
                </div>
                <p className="text-caption" style={{ marginTop: 4, color: "var(--text-tertiary)" }}>
                  Bepaalt de toon en schrijfstijl van de notulen.
                </p>
              </div>
              <div className="form-field">
                <label className="form-label">Wat moet er in de notulen staan?</label>
                <textarea
                  className="input"
                  value={form.notule_prompt}
                  onChange={(e) => setForm({ ...form, notule_prompt: e.target.value })}
                  rows={4}
                  placeholder="Bijv: Maak een beknopte samenvatting met actiepunten en besluiten. Gebruik een informele toon."
                  style={{ resize: "vertical" }}
                />
                <p className="text-caption" style={{ marginTop: 4, color: "var(--text-tertiary)" }}>
                  Beschrijf in je eigen woorden wat de AI moet doen: welke onderdelen, gewenste toon, en hoeveel detail.
                </p>
              </div>
              <div className="form-field">
                <label className="form-label">Secties (optioneel, gescheiden door komma&apos;s)</label>
                <input className="input" value={form.sections}
                  onChange={(e) => setForm({ ...form, sections: e.target.value })}
                  placeholder="Bijv. Onderwerpen, Acties, Open vragen" />
              </div>
              <details className="profile-advanced-section">
                <summary className="text-caption" style={{ cursor: "pointer", color: "var(--text-secondary)", userSelect: "none" }}>
                  Geavanceerde opties
                </summary>
                <div className="flex-col gap-10" style={{ marginTop: 10 }}>
                  <div className="form-field">
                    <div className="profile-prompt-header">
                      <label className="form-label">Rol van de AI</label>
                      <span className="text-caption" style={{ color: form.system_prompt.length > 4500 ? "var(--fill-system-critical)" : "var(--text-tertiary)" }}>
                        {form.system_prompt.length}/5000
                      </span>
                    </div>
                    <textarea
                      className="input"
                      value={form.system_prompt}
                      onChange={(e) => {
                        if (e.target.value.length <= 5000) {
                          setForm({ ...form, system_prompt: e.target.value });
                        }
                      }}
                      rows={3}
                      placeholder="Laat leeg voor de standaard rol. Vul in voor een specifieke persoonlijkheid of expertise."
                      style={{ resize: "vertical" }}
                    />
                  </div>
                  <div className="form-field">
                    <label className="form-label">HTML-sjabloon</label>
                    <textarea
                      className="input"
                      value={form.notule_template}
                      onChange={(e) => setForm({ ...form, notule_template: e.target.value })}
                      rows={3}
                      placeholder="Optioneel. Laat leeg voor de standaard opmaak."
                      style={{ resize: "vertical" }}
                    />
                  </div>
                </div>
              </details>
            </div>
            <div className="profile-modal-actions">
              <button onClick={() => onClose()} className="btn btn-secondary btn-sm">
                Annuleren
              </button>
              <button onClick={onSave} disabled={loading} className="btn btn-accent btn-sm">
                {loading ? "Opslaan..." : "Opslaan"}
              </button>
            </div>
          </div>
  );
}
