import { CLOUD_STT_PRESETS, type CloudSttProvider } from "../../types";
import { useSettingsStore } from "../../stores/settingsStore";
import { SettingsField, CredentialField } from "./SettingsFields";

/** Provider, model, base URL and key for the opt-in cloud transcription engine (DEC-074). */
export function CloudSttSettings() {
  const settings = useSettingsStore();
  const provider = settings.cloud_stt_provider;
  const preset = CLOUD_STT_PRESETS[provider] ?? CLOUD_STT_PRESETS.openai;

  function selectProvider(id: CloudSttProvider) {
    const models = CLOUD_STT_PRESETS[id].models;
    settings.updateSettings({
      cloud_stt_provider: id,
      cloud_stt_model: models.length && !models.includes(settings.cloud_stt_model) ? models[0] : settings.cloud_stt_model,
    });
  }

  return <div style={{ padding: "0 20px 12px" }}>
    <div className="action-row" role="group" aria-label="Aanbieder cloud-transcriptie" style={{ marginBottom: 12 }}>
      {(Object.keys(CLOUD_STT_PRESETS) as CloudSttProvider[]).map(id =>
        <button key={id} aria-pressed={provider === id} className={`btn btn-sm ${provider === id ? "btn-accent" : "btn-secondary"}`}
          onClick={() => selectProvider(id)}>{CLOUD_STT_PRESETS[id].label}</button>)}
    </div>
    {provider === "custom" && <SettingsField label="Adres">
      <input className="input" type="url" placeholder="https://api.example.com/v1" value={settings.cloud_stt_base_url}
        onChange={e => settings.updateSettings({ cloud_stt_base_url: e.target.value })} />
    </SettingsField>}
    <SettingsField label="Model">
      {preset.models.length
        ? <select className="select" aria-label="Transcriptiemodel cloud" style={{ width: "100%" }} value={settings.cloud_stt_model}
            onChange={e => settings.updateSettings({ cloud_stt_model: e.target.value })}>
            {preset.models.map(m => <option key={m} value={m}>{m}</option>)}
          </select>
        : <input className="input" type="text" aria-label="Transcriptiemodel cloud" placeholder="whisper-1" value={settings.cloud_stt_model}
            onChange={e => settings.updateSettings({ cloud_stt_model: e.target.value })} />}
    </SettingsField>
    <CredentialField key={preset.credentialKey} credentialKey={preset.credentialKey} label={`${preset.label} API-sleutel`} />
    <p className="settings-desc">
      Audio gaat naar {provider === "custom" ? "het opgegeven adres" : preset.label} voor transcriptie.
      {provider === "openai" && " De sleutel is dezelfde als voor OpenAI-notulen."}
    </p>
  </div>;
}
