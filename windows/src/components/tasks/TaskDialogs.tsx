import { useState } from "react";
import { DesktopDialog } from "../ui/DesktopDialog";
import { useProfilesStore } from "../../stores/profilesStore";
import { useSettingsStore } from "../../stores/settingsStore";
import { durationLabel, outcomeLabel, secondsBetween, type TaskHistoryEntry } from "../../services/taskHistory";
import { canReprocess, hasNotule, hasRecording, isRunning, renameTask, reprocessTask } from "../../services/taskActions";
import { isMetered, modelChoices, modelLabel, modelProvider, modelSettingKey } from "../../services/suggestedModels";

const panel = { maxWidth: 520, width: "calc(100% - 32px)", padding: 24, display: "flex", flexDirection: "column", gap: 14, overflowY: "auto" } as const;
const date = (iso?: string) => iso ? new Date(iso).toLocaleString("nl-NL", { dateStyle: "medium", timeStyle: "short" }) : "Nog niet";

export type TaskAction = "details" | "reprocess" | "delete-recording" | "delete";

/** Details of one history task with its actions. */
export function TaskDetailDialog({ entry, onAction, onOpenNotule, onClose }: {
  entry: TaskHistoryEntry; onAction: (action: TaskAction) => void; onOpenNotule: () => void; onClose: () => void;
}) {
  const total = secondsBetween(entry.created_at, entry.finished_at);
  const rows: [string, string][] = [
    ["Status", outcomeLabel(entry, isRunning(entry))],
    ["Profiel", entry.profile_name || entry.profile_id || "Onbekend"],
    ["Gestart", date(entry.created_at)],
    ["Klaar", date(entry.finished_at)],
    ["Verwerkingstijd", total != null ? durationLabel(total) : "Onbekend"],
    ["Lengte opname", entry.recording_seconds ? durationLabel(entry.recording_seconds) : "Onbekend"],
    ["Transcriptie", entry.transcription_engine || "Onbekend"],
    ["Notule", [entry.notule_provider, entry.notule_model].filter(Boolean).join(" · ") || "Onbekend"],
    ["Bestand", entry.filename || "Onbekend"],
    ["Opname", hasRecording(entry) ? "Aanwezig" : entry.recording_deleted ? "Verwijderd" : "Niet gevonden"],
    ["Notule opgeslagen", hasNotule(entry) ? "Ja" : "Nee"],
  ];
  return <DesktopDialog label={`Details van ${entry.title}`} onClose={onClose}>
    <section className="card" style={panel} onClick={e => e.stopPropagation()}>
      <h3 className="td-confirm-title" style={{ margin: 0, fontSize: 16 }}>{entry.title}</h3>
      {entry.error_message && entry.status !== "completed" && <div className="error-banner-inline" style={{ margin: 0 }}>{entry.error_message}</div>}
      <dl className="system-specs" style={{ margin: 0 }}>
        {rows.map(([label, value]) => <div key={label}><dt>{label}</dt><dd>{value}</dd></div>)}
      </dl>
      {entry.steps.length > 0 && <div>
        <p className="settings-desc" style={{ fontWeight: 600, margin: "0 0 4px" }}>Stappen</p>
        <dl className="system-specs" style={{ margin: 0 }}>
          {entry.steps.map((step, i) => {
            const seconds = secondsBetween(step.started_at, step.finished_at);
            return <div key={i}><dt>{step.label}</dt><dd>{seconds != null ? durationLabel(seconds) : "loopt"}</dd></div>;
          })}
        </dl>
      </div>}
      <div className="flex-row gap-8" style={{ flexWrap: "wrap" }}>
        <button className="btn btn-accent btn-sm" disabled={!canReprocess(entry)} onClick={() => onAction("reprocess")}>Opnieuw verwerken</button>
        {hasNotule(entry) && <button className="btn btn-sm" onClick={onOpenNotule}>Naar de notule</button>}
        <button className="btn btn-sm" disabled={!hasRecording(entry) || isRunning(entry)} onClick={() => onAction("delete-recording")}>Opname verwijderen</button>
        <button className="btn btn-sm" style={{ color: "var(--status-error)" }} disabled={isRunning(entry)} onClick={() => onAction("delete")}>Taak verwijderen</button>
        <button className="btn btn-sm" style={{ marginLeft: "auto" }} onClick={onClose}>Sluiten</button>
      </div>
    </section>
  </DesktopDialog>;
}

/** Title, profile and a suggested model (under the price cap) for a new run. */
export function ReprocessDialog({ entry, onClose }: { entry: TaskHistoryEntry; onClose: () => void }) {
  const profiles = useProfilesStore(s => s.profiles);
  const settings = useSettingsStore();
  const provider = modelProvider(settings);
  const current = settings[modelSettingKey(provider)];
  const choices = modelChoices(provider, current);
  const [title, setTitle] = useState(entry.title);
  const [profileId, setProfileId] = useState(profiles.find(p => p.id === entry.profile_id)?.id ?? profiles[0]?.id ?? "");
  const [model, setModel] = useState(choices.includes(current) ? current : choices[0] ?? "");
  return <DesktopDialog label="Opnieuw verwerken" onClose={onClose}>
    <section className="card" style={panel} onClick={e => e.stopPropagation()}>
      <h3 className="td-confirm-title" style={{ margin: 0, fontSize: 16 }}>Opnieuw verwerken</h3>
      <label className="flex-col gap-4"><span className="settings-desc">Titel</span>
        <input className="input" value={title} onChange={e => setTitle(e.target.value)} /></label>
      <label className="flex-col gap-4"><span className="settings-desc">Profiel</span>
        <select className="select" value={profileId} onChange={e => setProfileId(e.target.value)}>
          {profiles.map(p => <option key={p.id} value={p.id}>{p.name}</option>)}
        </select></label>
      {choices.length > 1 ? <label className="flex-col gap-4"><span className="settings-desc">Model</span>
        <select className="select" aria-label="Model" value={model} onChange={e => setModel(e.target.value)}>
          {choices.map(m => <option key={m} value={m}>{modelLabel(m)}</option>)}
        </select>
        <span className="settings-desc">{isMetered(provider)
          ? "Je ziet alleen aanbevolen modellen tot $3 per miljoen invoertokens en $15 per miljoen uitvoertokens. "
          : ""}Je keuze wordt ook je standaardmodel bij Instellingen.</span>
      </label> : <p className="settings-desc" style={{ margin: 0 }}>Model: {current || "standaard"}</p>}
      <p className="settings-desc" style={{ margin: 0 }}>{entry.status === "completed"
        ? "De opname wordt opnieuw verwerkt tot een nieuwe notule. De bestaande notule blijft staan."
        : "De opname wordt opnieuw verwerkt. Een al opgeslagen transcriptie wordt hergebruikt."}</p>
      <div className="flex-row gap-8" style={{ justifyContent: "flex-end", flexWrap: "wrap" }}>
        <button className="btn" onClick={onClose}>Annuleren</button>
        <button className="btn" disabled={!title.trim()} onClick={() => { renameTask(entry, title); onClose(); }}>Titel opslaan</button>
        <button className="btn btn-accent" disabled={!profileId || !canReprocess(entry)}
          onClick={() => { reprocessTask(entry, title, profileId, choices.length > 1 ? model : undefined); onClose(); }}>Opnieuw verwerken</button>
      </div>
    </section>
  </DesktopDialog>;
}

/** Delete confirmation: the notule is only removed when the user picks that button. */
export function DeleteTaskDialog({ entry, onDelete, onClose }: {
  entry: TaskHistoryEntry; onDelete: (includeNotule: boolean) => void; onClose: () => void;
}) {
  return <DesktopDialog label="Taak verwijderen" onClose={onClose}>
    <section className="td-confirm" style={{ maxWidth: 420 }} onClick={e => e.stopPropagation()}>
      <h3 className="td-confirm-title">Taak verwijderen</h3>
      <p className="td-confirm-text">"{entry.title}" verdwijnt uit Taken. De notule en de opname blijven bewaard, tenzij je kiest voor Taak en notule verwijderen.</p>
      <div className="td-confirm-actions" style={{ flexWrap: "wrap" }}>
        <button autoFocus className="btn btn-secondary" onClick={onClose}>Terug</button>
        {hasNotule(entry) && <button className="btn btn-danger" onClick={() => onDelete(true)}>Taak en notule verwijderen</button>}
        <button className="btn btn-danger" onClick={() => onDelete(false)}>Alleen taak verwijderen</button>
      </div>
    </section>
  </DesktopDialog>;
}
