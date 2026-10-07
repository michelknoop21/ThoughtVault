import { useEffect, useState } from "react";
import { useSettingsStore } from "../../stores/settingsStore";
import { loadCredential, storeCredential } from "../../services/tauriCommands";

export function CloudAISettings() {
  const settings = useSettingsStore();
  const config = settings.cloud_providers.find((item) => item.id === settings.selected_cloud_provider);
  const key = settings.notulen_provider === "ollama-cloud" ? "ollamaApiKey" : config ? `cloudAI-${config.id}` : "";
  const [apiKey, setApiKey] = useState("");
  const [status, setStatus] = useState("");
  useEffect(() => {
    let active = true;
    setApiKey(""); setStatus("");
    if (key) void loadCredential(key).then((value) => { if (active) setApiKey(value ?? ""); }).catch(() => { if (active) setStatus("Sleutel laden mislukt."); });
    return () => { active = false; };
  }, [key]);
  function update(patch: Partial<NonNullable<typeof config>>) {
    settings.updateSettings({ cloud_providers: settings.cloud_providers.map((item) => item.id === config?.id ? { ...item, ...patch } : item) });
  }
  if (!["ollama-cloud", "openai-compatible"].includes(settings.notulen_provider)) return null;
  return <div className="flex-col gap-10">
    {settings.notulen_provider === "ollama-cloud" ? <>
      <p>Ollama Cloud · https://ollama.com</p>
      <label>Cloudmodel<input className="input" value={settings.ollama_cloud_model} onChange={(e) => settings.updateSettings({ ollama_cloud_model: e.target.value })} /></label>
    </> : <>
      <label>Opgeslagen provider<select className="select" value={settings.selected_cloud_provider} onChange={(e) => settings.updateSettings({ selected_cloud_provider: e.target.value })}>
        <option value="">Selecteer provider</option>
        {settings.cloud_providers.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}
      </select></label>
      <button className="btn btn-secondary btn-sm" onClick={() => {
        const id = crypto.randomUUID();
        settings.updateSettings({ cloud_providers: [...settings.cloud_providers, { id, name: "Nieuwe provider", base_url: "https://api.openai.com/v1", model: "" }], selected_cloud_provider: id });
      }}>Provider toevoegen</button>
      {config && <>
        <label>Naam<input className="input" value={config.name} onChange={(e) => update({ name: e.target.value })} /></label>
        <label>HTTPS-adres<input className="input" type="url" value={config.base_url} onChange={(e) => update({ base_url: e.target.value })} /></label>
        <label>Model<input className="input" value={config.model} onChange={(e) => update({ model: e.target.value })} /></label>
      </>}
    </>}
    {key && <>
      <label>API-sleutel<input className="input" type="password" value={apiKey} onChange={(e) => setApiKey(e.target.value)} /></label>
      <button className="btn btn-secondary btn-sm" onClick={() => { void storeCredential(key, apiKey).then(() => setStatus("Sleutel opgeslagen in de systeemkeyring.")).catch(() => setStatus("Sleutel opslaan mislukt. Probeer opnieuw.")); }}>Sleutel opslaan</button>
    </>}
    <p role="status">{status}</p>
  </div>;
}
