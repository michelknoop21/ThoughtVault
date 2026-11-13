import { DesktopDialog } from "../components/ui/DesktopDialog";
import { useState, useEffect, useRef } from "react";
import { Dismiss24Regular, Checkmark24Regular, Person24Regular } from "../components/ui/StudioIcons";
import { usePeopleDirectoryStore } from "../stores/peopleDirectoryStore";
import { HistoryList } from "../components/settings/HistoryList";
import type { HistoryEntry } from "../services/contextHistory";
import type { PersonProfile } from "../types";

interface PersonEditModalProps {
  person: PersonProfile;  // pre-populated for edit; factory defaults for new
  isNew: boolean;
  onClose: () => void;
  /** Called right after a new person was added (before the modal closes). */
  onAdded?: (person: PersonProfile) => void;
}

/** "Jan de Vries" -> "JV"; empty when there is no name yet. */
export function initials(name: string): string {
  const words = name.trim().split(/\s+/).filter(Boolean);
  if (words.length === 0) return "";
  return (words[0][0] + (words.length > 1 ? words[words.length - 1][0] : "")).toUpperCase();
}

function splitAndTrim(value: string): string[] {
  return value
    .split(",")
    .map((s) => s.trim())
    .filter((s) => s.length > 0);
}

export function PersonEditModal({ person, isNew, onClose, onAdded }: PersonEditModalProps) {
  const addPerson = usePeopleDirectoryStore((s) => s.addPerson);
  const recordUpdate = usePeopleDirectoryStore((s) => s.recordUpdate);

  const [name, setName] = useState(person.name);
  const [role, setRole] = useState(person.role);
  const [organization, setOrganization] = useState(person.organization);
  const [aliasesText, setAliasesText] = useState(person.aliases.join(", "));
  const [expertiseText, setExpertiseText] = useState(person.expertiseTags.join(", "));
  // Tri-state: "true" | "false" | "null" (string for select value)
  const [isInternalValue, setIsInternalValue] = useState<"true" | "false" | "null">(
    person.isInternal === true ? "true" : person.isInternal === false ? "false" : "null"
  );

  const [tasks, setTasks] = useState<string[]>(person.responsibilities ?? []);
  const [newTask, setNewTask] = useState("");
  const [historyKey, setHistoryKey] = useState(0);

  const [isSaving, setIsSaving] = useState(false);
  const [savedOk, setSavedOk] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);

  const savedTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const firstInputRef = useRef<HTMLInputElement>(null);

  // Focus first input on mount
  useEffect(() => {
    firstInputRef.current?.focus();
    return () => {
      if (savedTimerRef.current) clearTimeout(savedTimerRef.current);
    };
  }, []);

  /** Trims and ignores duplicates, case-insensitive. */
  function addTask() {
    const task = newTask.trim();
    if (!task) return;
    if (!tasks.some((t) => t.toLowerCase() === task.toLowerCase())) setTasks([...tasks, task]);
    setNewTask("");
  }

  /** Puts an earlier version back and shows it in the fields. */
  async function restore(entry: HistoryEntry) {
    if (isSaving) return;
    setIsSaving(true);
    try {
      await usePeopleDirectoryStore.getState().restorePerson(entry);
      const fresh = usePeopleDirectoryStore.getState().people.find((p) => p.id === person.id);
      if (fresh) {
        setName(fresh.name); setRole(fresh.role); setOrganization(fresh.organization);
        setAliasesText(fresh.aliases.join(", ")); setExpertiseText(fresh.expertiseTags.join(", "));
        setIsInternalValue(fresh.isInternal === true ? "true" : fresh.isInternal === false ? "false" : "null");
        setTasks(fresh.responsibilities ?? []);
      }
      setSaveError(null);
    } catch (err) {
      setSaveError(`Herstellen mislukt: ${err instanceof Error ? err.message : String(err)}`);
    } finally {
      setIsSaving(false);
    }
  }

  function parseIsInternal(value: "true" | "false" | "null"): boolean | null {
    if (value === "true") return true;
    if (value === "false") return false;
    return null;
  }

  async function handleSave() {
    if (isSaving) return;
    setIsSaving(true);
    setSaveError(null);

    try {
      const updates = {
        name: name.trim(),
        role: role.trim(),
        organization: organization.trim(),
        aliases: splitAndTrim(aliasesText),
        expertiseTags: splitAndTrim(expertiseText),
        isInternal: parseIsInternal(isInternalValue),
        responsibilities: tasks,
      };

      // A new person keeps the emails and meeting types it was created with; an edit only
      // sends the fields shown here, so changes made elsewhere meanwhile are not overwritten.
      if (isNew) {
        addPerson({ ...person, ...updates });
        onAdded?.({ ...person, ...updates });
      } else {
        // The store keeps the previous version in the history.
        await recordUpdate(person.id, "handmatig", updates);
        setHistoryKey((k) => k + 1);
      }

      setSavedOk(true);
      savedTimerRef.current = setTimeout(() => {
        onClose();
      }, 2000);
    } catch (err) {
      setSaveError("Kon persoon niet opslaan. Probeer het opnieuw.");
    } finally {
      setIsSaving(false);
    }
  }

  return (
    /* Overlay backdrop */
    <DesktopDialog label={isNew ? "Persoon toevoegen" : "Persoon bewerken"} onClose={onClose}>
      {/* Modal panel */}
      <div
        className="person-editor"
        role="dialog"
        aria-modal="true"
        aria-label={isNew ? "Persoon toevoegen" : `${name || "Persoon"} bewerken`}
      >
        {/* Modal header */}
        <div className="person-editor-head">
          <span className="person-avatar" aria-hidden="true">{initials(name) || <Person24Regular />}</span>
          <h2>{isNew ? "Persoon toevoegen" : "Persoon bewerken"}</h2>
          <button className="person-editor-close" onClick={onClose} aria-label="Sluiten" title="Sluiten">
            <Dismiss24Regular style={{ fontSize: 16 }} />
          </button>
        </div>

        {/* Scrollable form body */}
        <div className="person-editor-fields">

          {/* Naam */}
          <div className="flex-col gap-4">
            <label>
              Naam
            </label>
            <input
              ref={firstInputRef}
              type="text"
              className="input"
              aria-label="Naam"
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="Volledige naam"
              disabled={isSaving || savedOk}
            />
          </div>

          {/* Rol / Functie */}
          <div className="flex-col gap-4">
            <label>
              Rol / Functie
            </label>
            <input
              type="text"
              className="input"
              aria-label="Rol / Functie"
              value={role}
              onChange={(e) => setRole(e.target.value)}
              placeholder="Bijv. Projectmanager"
              disabled={isSaving || savedOk}
            />
          </div>

          {/* Organisatie */}
          <div className="flex-col gap-4">
            <label>
              Organisatie
            </label>
            <input
              type="text"
              className="input"
              aria-label="Organisatie"
              value={organization}
              onChange={(e) => setOrganization(e.target.value)}
              placeholder="Bijv. Prezent BV"
              disabled={isSaving || savedOk}
            />
          </div>

          {/* Aliassen */}
          <div className="flex-col gap-4">
            <label>
              Aliassen
            </label>
            <input
              type="text"
              className="input"
              aria-label="Aliassen"
              value={aliasesText}
              onChange={(e) => setAliasesText(e.target.value)}
              placeholder="Michel, Knoop, MK (kommagescheiden)"
              disabled={isSaving || savedOk}
            />
          </div>

          {/* Expertise / onderwerpen */}
          <div className="flex-col gap-4">
            <label>
              Expertise / onderwerpen
            </label>
            <input
              type="text"
              className="input"
              aria-label="Expertise / onderwerpen"
              value={expertiseText}
              onChange={(e) => setExpertiseText(e.target.value)}
              placeholder="grafisch ontwerp, marketing, IT (kommagescheiden)"
              disabled={isSaving || savedOk}
            />
          </div>

          {/* Intern / extern tri-state */}
          <div className="flex-col gap-4">
            <label>
              Intern / extern
            </label>
            <select
              className="input"
              aria-label="Intern / extern"
              value={isInternalValue}
              onChange={(e) => setIsInternalValue(e.target.value as "true" | "false" | "null")}
              disabled={isSaving || savedOk}
            >
              <option value="null">Onbekend</option>
              <option value="true">Intern</option>
              <option value="false">Extern</option>
            </select>
          </div>

          {/* Taken en verantwoordelijkheden */}
          <div className="flex-col gap-4">
            <label>
              Taken en verantwoordelijkheden
            </label>
            {tasks.map((task, index) => (
              <div key={`${task}-${index}`} className="person-task-row">
                <span>{task}</span>
                <button className="person-task-remove" aria-label={`Verwijder ${task}`} data-log-label="Taak verwijderen" title="Verwijderen"
                  onClick={() => setTasks(tasks.filter((_, i) => i !== index))} disabled={isSaving || savedOk}>
                  <Dismiss24Regular style={{ fontSize: 14 }} />
                </button>
              </div>
            ))}
            <div className="person-task-row">
              <input type="text" className="input" aria-label="Nieuwe taak" placeholder="Nieuwe taak" value={newTask}
                onChange={(e) => setNewTask(e.target.value)} onKeyDown={(e) => { if (e.key === "Enter") addTask(); }}
                disabled={isSaving || savedOk} />
              <button className="btn btn-secondary btn-sm" onClick={addTask} disabled={!newTask.trim() || isSaving || savedOk}>Toevoegen</button>
            </div>
          </div>

          {!isNew && (
            <div className="flex-col gap-4">
              <label>Geschiedenis</label>
              <HistoryList key={historyKey} kind="person" itemId={person.id} onRestore={restore} disabled={isSaving || savedOk} />
            </div>
          )}
        </div>

        {/* Modal footer */}
        <div className="person-editor-foot">
          {saveError && <p role="alert">{saveError}</p>}
          <div className="person-editor-actions">
            <button className="btn" onClick={onClose}>Annuleren</button>
            <button className="btn btn-primary" onClick={handleSave} disabled={isSaving || savedOk || !name.trim()}>
              {savedOk ? (
                <>
                  <Checkmark24Regular style={{ fontSize: 16 }} />
                  Opgeslagen
                </>
              ) : isSaving ? (
                "Opslaan..."
              ) : (
                isNew ? "Persoon toevoegen" : "Wijzigingen opslaan"
              )}
            </button>
          </div>
        </div>
      </div>
    </DesktopDialog>
  );
}
