import { useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { open } from "@tauri-apps/plugin-shell";
import { useSettingsStore } from "../../stores/settingsStore";
import { loadCredential, storeCredential } from "../../services/tauriCommands";
import { OLLAMA_LOCAL_URL, isOllamaCloudURL } from "../../services/ollamaModels";
import { DEFAULT_SETTINGS, type AppSettings, type NotulenProvider } from "../../types";
import { DesktopDialog } from "../ui/DesktopDialog";
import "../../styles/onboarding.css";

/** Wizard step "Wie schrijft je notulen?": provider, key and model before the first recording. */
export type NotulenChoice = "openrouter" | "local" | "other";
type KeyedProvider = "openrouter" | "openai" | "anthropic";
type KeyState = "idle" | "testing" | "ok" | "rejected" | "unreachable" | "error";

export function choiceFor(provider: NotulenProvider): NotulenChoice {
  if (provider === "ollama" || provider === "lm-studio") return "local";
  if (provider === "openai" || provider === "anthropic") return "other";
  return "openrouter";
}

const KEYED: Record<KeyedProvider, { name: string; check: string; keys: string; headers: (key: string) => Record<string, string> }> = {
  openrouter: { name: "OpenRouter", check: "https://openrouter.ai/api/v1/key", keys: "https://openrouter.ai/settings/keys", headers: key => ({ Authorization: `Bearer ${key}` }) },
  openai: { name: "OpenAI", check: "https://api.openai.com/v1/models", keys: "https://platform.openai.com/api-keys", headers: key => ({ Authorization: `Bearer ${key}` }) },
  anthropic: { name: "Anthropic", check: "https://api.anthropic.com/v1/models", keys: "https://console.anthropic.com/settings/keys", headers: key => ({ "x-api-key": key, "anthropic-version": "2023-06-01" }) },
};

/** OpenRouter lists models without a key, so each provider is asked about the key itself. */
export async function testKey(provider: KeyedProvider, key: string): Promise<KeyState> {
  try {
    const { status } = await invoke<{ status: number }>("proxy_request", {
      request: { url: KEYED[provider].check, method: "GET", headers: KEYED[provider].headers(key), body: null, timeout_seconds: 10 },
    });
    if (status === 200) return "ok";
    return status === 401 || status === 403 ? "rejected" : "unreachable";
  } catch { return "unreachable"; }
}

const TILES: [NotulenChoice, string, string][] = [
  ["openrouter", "OpenRouter", "Eén sleutel voor veel modellen."],
  ["local", "Op deze pc", "Via Ollama, gratis, vraagt een snelle pc."],
  ["other", "Andere aanbieder", "Eigen sleutel bij OpenAI of Claude."],
];

const MODEL_FIELD = { openrouter: "openrouter_model", openai: "openai_model", anthropic: "anthropic_model" } as const;

export function NotulenStep({ onBack, onDone }: { onBack: () => void; onDone: () => void }) {
  const settings = useSettingsStore();
  const [choice, setChoice] = useState<NotulenChoice>(() => choiceFor(settings.notulen_provider));
  const [other, setOther] = useState<"openai" | "anthropic">(settings.notulen_provider === "anthropic" ? "anthropic" : "openai");
  const keyed: KeyedProvider | null = choice === "openrouter" ? "openrouter" : choice === "other" ? other : null;
  const [draft, setDraft] = useState("");
  const [saved, setSaved] = useState(false);
  const [keyState, setKeyState] = useState<KeyState>("idle");
  const [keyError, setKeyError] = useState("");
  const [askSkip, setAskSkip] = useState(false);

  useEffect(() => {
    let active = true;
    setDraft(""); setSaved(false); setKeyState("idle");
    if (keyed) loadCredential(`${keyed}_api_key`).then(key => { if (active) setSaved(Boolean(key)); }).catch(() => {});
    return () => { active = false; };
  }, [keyed]);

  /** Stores a typed key; false when Windows Credential Manager refused it. */
  async function saveDraft(): Promise<boolean> {
    if (!keyed || !draft.trim()) return true;
    try {
      await storeCredential(`${keyed}_api_key`, draft.trim());
      setSaved(true);
      return true;
    } catch (error) {
      setKeyError(typeof error === "string" ? error : "Opslaan in Windows Credential Manager mislukt.");
      setKeyState("error");
      return false;
    }
  }

  async function handleTest() {
    if (!keyed) return;
    setKeyState("testing");
    const key = draft.trim();
    if (!await saveDraft()) return;
    setKeyState(await testKey(keyed, key || await loadCredential(`${keyed}_api_key`) || ""));
  }

  async function handleNext() {
    if (!await saveDraft()) return;
    if (keyed && !saved && !draft.trim()) { setAskSkip(true); return; }
    const current = settings.notulen_provider;
    if (choice === "local") {
      const provider = current === "lm-studio" ? "lm-studio" : "ollama";
      settings.updateSettings(provider === "ollama" ? {
        notulen_provider: "ollama",
        ollama_url: isOllamaCloudURL(settings.ollama_url) ? OLLAMA_LOCAL_URL : settings.ollama_url,
        ollama_model: settings.ollama_model || DEFAULT_SETTINGS.ollama_model,
      } : { notulen_provider: provider });
    } else {
      settings.updateSettings({ notulen_provider: keyed! });
    }
    onDone();
  }

  const name = keyed ? KEYED[keyed].name : "";
  const modelField = keyed ? MODEL_FIELD[keyed] : null;
  return <div className="onb-notulen">
    <h1 className="onb-title">Wie schrijft je notulen?</h1>
    <p className="onb-lead">Opnemen en omzetten naar tekst gebeurt op je eigen pc. Voor de notule kies je een taalmodel.</p>
    <div className="onb-tiles" role="radiogroup" aria-label="Aanbieder voor notulen">
      {TILES.map(([id, title, subtitle]) => <button key={id} type="button" role="radio" aria-checked={choice === id}
        className="onb-tile" onClick={() => setChoice(id)}>
        <span className="onb-tile-head"><strong>{title}</strong>{id === "openrouter" && <span className="onb-badge">Aanbevolen</span>}</span>
        <span className="onb-muted">{subtitle}</span>
      </button>)}
    </div>

    {choice === "other" && <div className="onb-segment" role="radiogroup" aria-label="Andere aanbieder">
      {(["openai", "anthropic"] as const).map(id => <button key={id} type="button" role="radio" aria-checked={other === id}
        onClick={() => setOther(id)}>{id === "openai" ? "OpenAI" : "Claude"}</button>)}
    </div>}

    {keyed ? <div className="onb-key">
      <div className="onb-key-label"><label htmlFor="onb-key-input">Sleutel van {name}</label>
        <button type="button" className="onb-link" onClick={() => void open(KEYED[keyed].keys)}>Waar vind ik mijn sleutel?</button></div>
      <div className="onb-key-row">
        <input id="onb-key-input" className="input onb-key-input" type="password" autoComplete="off" spellCheck={false} value={draft}
          onChange={event => { setDraft(event.target.value); setKeyState("idle"); }}
          placeholder={saved ? "Sleutel opgeslagen · plak een nieuwe om te vervangen" : "Plak je sleutel"} />
        <button type="button" className="btn btn-secondary" disabled={keyState === "testing" || (!draft.trim() && !saved)} onClick={() => void handleTest()}>Testen</button>
      </div>
      <div className="onb-key-status" role="status" aria-live="polite">
        {keyState === "testing" && <><span className="onb-spinner" aria-hidden="true" />Sleutel testen…</>}
        {keyState === "ok" && <><span className="onb-ok">Sleutel werkt</span><span className="onb-muted">De sleutel staat in Windows Credential Manager, niet in de app.</span></>}
        {keyState === "rejected" && <span className="onb-error">{name} weigert deze sleutel. Controleer of je hem volledig hebt geplakt.</span>}
        {keyState === "unreachable" && <span className="onb-error">{name} is niet bereikbaar. Controleer je internetverbinding.</span>}
        {keyState === "error" && <span className="onb-error">{keyError}</span>}
      </div>
    </div> : <p className="onb-note">Ollama schrijft de notule op deze pc. Installeer Ollama en kies het model later in Instellingen › Verwerking.</p>}

    {/* Spot for the model tiers (Snel / Gebalanceerd / Grondig) once the suggested-model catalog lands. */}
    {modelField && <div className="onb-model">
      <h2>Kies een model</h2>
      <p className="onb-muted">Het aanbevolen model staat al ingevuld. Later wisselen kan in Instellingen › Verwerking.</p>
      <input className="input onb-model-input" type="text" aria-label={`Model van ${name}`} value={settings[modelField]}
        onChange={event => settings.updateSettings({ [modelField]: event.target.value } as Partial<AppSettings>)} />
    </div>}

    <div className="onb-footer">
      <button type="button" className="onb-link onb-skip" onClick={() => setAskSkip(true)}>Overslaan</button>
      <span className="onb-muted onb-later">Je kunt dit later doen.</span>
      <span className="onb-spacer" />
      <button type="button" className="btn btn-secondary" onClick={onBack}>Terug</button>
      <button type="button" className="btn btn-accent" onClick={() => void handleNext()}>Volgende</button>
    </div>

    {askSkip && <DesktopDialog label="Zonder taalmodel verder?" onClose={() => setAskSkip(false)}>
      <section className="onb-dialog" role="alertdialog" aria-labelledby="onb-skip-title" aria-describedby="onb-skip-text">
        <span className="onb-dialog-icon" aria-hidden="true">!</span>
        <h2 id="onb-skip-title">Zonder taalmodel verder?</h2>
        <p id="onb-skip-text">Opnemen en omzetten naar tekst werken gewoon. Notulen maakt de app pas als je een model kiest in Instellingen › Verwerking.</p>
        <div className="onb-dialog-actions">
          <button type="button" className="btn btn-secondary" onClick={() => { setAskSkip(false); onDone(); }}>Toch overslaan</button>
          <button type="button" className="btn btn-accent" autoFocus onClick={() => setAskSkip(false)}>Model kiezen</button>
        </div>
      </section>
    </DesktopDialog>}
  </div>;
}
