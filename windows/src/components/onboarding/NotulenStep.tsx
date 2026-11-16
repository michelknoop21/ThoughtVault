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

/** Short hash, so a refused key can be recognised without keeping the key itself. */
export function fingerprint(key: string): string {
  let hash = 0x811c9dc5;
  for (let i = 0; i < key.length; i++) hash = Math.imul(hash ^ key.charCodeAt(i), 0x01000193);
  return (hash >>> 0).toString(16);
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
  const typed = draft.trim();
  /** Which providers have a key in Credential Manager. */
  const [saved, setSaved] = useState<Partial<Record<KeyedProvider, boolean>>>({});
  /** Last test or save, tied to the provider and key it ran for, so a late result never lands on another tile or key. */
  const [check, setCheck] = useState<{ provider: KeyedProvider; key: string; state: KeyState; error?: string } | null>(null);
  /** Fingerprint of the key each provider refused (401/403). Only a passing test or another key lifts it. */
  const [rejected, setRejected] = useState<Partial<Record<KeyedProvider, string>>>({});
  const refusedShown = keyed !== null && Boolean(rejected[keyed]) && (!typed || fingerprint(typed) === rejected[keyed]);
  const checked: KeyState = check && check.provider === keyed && check.key === typed ? check.state : "idle";
  const keyState: KeyState = checked === "idle" && refusedShown ? "rejected" : checked;
  const [saving, setSaving] = useState(false);
  const [askSkip, setAskSkip] = useState(false);

  useEffect(() => {
    setDraft("");
    if (keyed) loadCredential(`${keyed}_api_key`)
      .then(key => setSaved(s => keyed in s ? s : { ...s, [keyed]: Boolean(key) })).catch(() => {});
  }, [keyed]);

  /** Stores a typed key; false when Windows Credential Manager refused it. */
  async function saveDraft(provider: KeyedProvider | null, key: string): Promise<boolean> {
    if (!provider || !key) return true;
    try {
      await storeCredential(`${provider}_api_key`, key);
      setSaved(s => ({ ...s, [provider]: true }));
      return true;
    } catch (error) {
      setCheck({ provider, key, state: "error", error: typeof error === "string" ? error : "Opslaan in Windows Credential Manager mislukt." });
      return false;
    }
  }

  async function handleTest() {
    if (!keyed) return;
    const provider = keyed, key = typed;
    setCheck({ provider, key, state: "testing" });
    if (!await saveDraft(provider, key)) return;
    const tested = key || await loadCredential(`${provider}_api_key`) || "";
    const state = await testKey(provider, tested);
    // A timeout or server error says nothing about the key: an earlier refusal stays.
    if (state === "ok") setRejected(r => ({ ...r, [provider]: undefined }));
    if (state === "rejected") setRejected(r => ({ ...r, [provider]: fingerprint(tested) }));
    setCheck(c => c?.provider === provider && c.key === key ? { provider, key, state } : c);
  }

  /** True when the key Volgende would install is the one the provider refused. */
  async function isRefused(provider: KeyedProvider): Promise<boolean> {
    const refused = rejected[provider];
    if (!refused) return false;
    return fingerprint(typed || await loadCredential(`${provider}_api_key`).catch(() => null) || "") === refused;
  }

  async function handleNext() {
    if (saving) return;
    setSaving(true);
    const refused = keyed !== null && await isRefused(keyed);
    const stored = !refused && await saveDraft(keyed, typed);
    setSaving(false);
    // A refused key cannot write a notule.
    if (refused) { setAskSkip(true); return; }
    if (!stored) return;
    if (keyed && !saved[keyed] && !typed) { setAskSkip(true); return; }
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
        className="onb-tile" disabled={saving} onClick={() => setChoice(id)}>
        <span className="onb-tile-head"><strong>{title}</strong>{id === "openrouter" && <span className="onb-badge">Aanbevolen</span>}</span>
        <span className="onb-muted">{subtitle}</span>
      </button>)}
    </div>

    {choice === "other" && <div className="onb-segment" role="radiogroup" aria-label="Andere aanbieder">
      {(["openai", "anthropic"] as const).map(id => <button key={id} type="button" role="radio" aria-checked={other === id} disabled={saving}
        onClick={() => setOther(id)}>{id === "openai" ? "OpenAI" : "Claude"}</button>)}
    </div>}

    {keyed ? <div className="onb-key">
      <div className="onb-key-label"><label htmlFor="onb-key-input">Sleutel van {name}</label>
        <button type="button" className="onb-link" onClick={() => void open(KEYED[keyed].keys)}>Waar vind ik mijn sleutel?</button></div>
      <div className="onb-key-row">
        <input id="onb-key-input" className="input onb-key-input" type="password" autoComplete="off" spellCheck={false} value={draft}
          onChange={event => setDraft(event.target.value)}
          placeholder={saved[keyed] ? "Sleutel opgeslagen · plak een nieuwe om te vervangen" : "Plak je sleutel"} />
        <button type="button" className="btn btn-secondary" disabled={saving || keyState === "testing" || (!typed && !saved[keyed])} onClick={() => void handleTest()}>Testen</button>
      </div>
      <div className="onb-key-status" role="status" aria-live="polite">
        {keyState === "testing" && <><span className="onb-spinner" aria-hidden="true" />Sleutel testen…</>}
        {keyState === "ok" && <><span className="onb-ok">Sleutel werkt</span><span className="onb-muted">De sleutel staat in Windows Credential Manager, niet in de app.</span></>}
        {keyState === "rejected" && <span className="onb-error">{name} weigert deze sleutel. Controleer of je hem volledig hebt geplakt.</span>}
        {keyState === "unreachable" && <span className="onb-error">{name} is niet bereikbaar. Controleer je internetverbinding.</span>}
        {keyState === "error" && <span className="onb-error">{check?.error}</span>}
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
      <button type="button" className="onb-link onb-skip" disabled={saving} onClick={() => setAskSkip(true)}>Overslaan</button>
      <span className="onb-muted onb-later">Je kunt dit later doen.</span>
      <span className="onb-spacer" />
      <button type="button" className="btn btn-secondary" disabled={saving} onClick={onBack}>Terug</button>
      <button type="button" className="btn btn-accent" disabled={saving} onClick={() => void handleNext()}>Volgende</button>
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
