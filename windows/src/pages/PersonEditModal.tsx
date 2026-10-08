import { DesktopDialog } from "../components/ui/DesktopDialog";
import { useState, useEffect, useRef } from "react";
import { Dismiss24Regular, Checkmark24Regular } from "@fluentui/react-icons";
import { usePeopleDirectoryStore } from "../stores/peopleDirectoryStore";
import type { PersonProfile } from "../types";

interface PersonEditModalProps {
  person: PersonProfile;  // pre-populated for edit; factory defaults for new
  isNew: boolean;
  onClose: () => void;
}

function splitAndTrim(value: string): string[] {
  return value
    .split(",")
    .map((s) => s.trim())
    .filter((s) => s.length > 0);
}

export function PersonEditModal({ person, isNew, onClose }: PersonEditModalProps) {
  const addPerson = usePeopleDirectoryStore((s) => s.addPerson);
  const updatePerson = usePeopleDirectoryStore((s) => s.updatePerson);

  const [name, setName] = useState(person.name);
  const [role, setRole] = useState(person.role);
  const [organization, setOrganization] = useState(person.organization);
  const [aliasesText, setAliasesText] = useState(person.aliases.join(", "));
  const [expertiseText, setExpertiseText] = useState(person.expertiseTags.join(", "));
  // Tri-state: "true" | "false" | "null" (string for select value)
  const [isInternalValue, setIsInternalValue] = useState<"true" | "false" | "null">(
    person.isInternal === true ? "true" : person.isInternal === false ? "false" : "null"
  );

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

  // Close on Escape
  useEffect(() => {
    function handleKeyDown(e: KeyboardEvent) {
      if (e.key === "Escape") onClose();
    }
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [onClose]);

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
        emails: person.emails,
        meetingTypes: person.meetingTypes,
      };

      if (isNew) {
        addPerson({ ...person, ...updates });
      } else {
        updatePerson(person.id, updates);
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
        style={{
          background: "var(--surface-primary)",
          borderRadius: "var(--radius-md)",
          border: "1px solid var(--stroke-card)",
          width: "100%",
          maxWidth: 480,
          maxHeight: "90vh",
          display: "flex",
          flexDirection: "column",
          overflow: "hidden",
        }}
        role="dialog"
        aria-modal="true"
        aria-label={isNew ? "Persoon toevoegen" : `${name || "Persoon"} bewerken`}
      >
        {/* Modal header */}
        <div
          style={{
            display: "flex",
            alignItems: "center",
            justifyContent: "space-between",
            padding: "16px 20px",
            borderBottom: "1px solid var(--stroke-divider)",
          }}
        >
          <h2
            style={{
              font: "var(--type-subtitle)",
              color: "var(--text-primary)",
              margin: 0,
            }}
          >
            {isNew ? "Persoon toevoegen" : "Persoon bewerken"}
          </h2>
          <button
            className="btn btn-ghost btn-sm"
            onClick={onClose}
            aria-label="Sluiten"
            title="Sluiten"
          >
            <Dismiss24Regular style={{ fontSize: 16 }} />
          </button>
        </div>

        {/* Scrollable form body */}
        <div style={{ overflowY: "auto", padding: "20px", display: "flex", flexDirection: "column", gap: 16 }}>

          {/* Naam */}
          <div className="flex-col gap-4">
            <label
              style={{ fontSize: "var(--font-body)", fontWeight: 500, color: "var(--text-primary)" }}
            >
              Naam
            </label>
            <input
              ref={firstInputRef}
              type="text"
              className="input"
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="Volledige naam"
              disabled={isSaving || savedOk}
            />
          </div>

          {/* Rol / Functie */}
          <div className="flex-col gap-4">
            <label
              style={{ fontSize: "var(--font-body)", fontWeight: 500, color: "var(--text-primary)" }}
            >
              Rol / Functie
            </label>
            <input
              type="text"
              className="input"
              value={role}
              onChange={(e) => setRole(e.target.value)}
              placeholder="Bijv. Projectmanager"
              disabled={isSaving || savedOk}
            />
          </div>

          {/* Organisatie */}
          <div className="flex-col gap-4">
            <label
              style={{ fontSize: "var(--font-body)", fontWeight: 500, color: "var(--text-primary)" }}
            >
              Organisatie
            </label>
            <input
              type="text"
              className="input"
              value={organization}
              onChange={(e) => setOrganization(e.target.value)}
              placeholder="Bijv. Prezent BV"
              disabled={isSaving || savedOk}
            />
          </div>

          {/* Aliassen */}
          <div className="flex-col gap-4">
            <label
              style={{ fontSize: "var(--font-body)", fontWeight: 500, color: "var(--text-primary)" }}
            >
              Aliassen
            </label>
            <input
              type="text"
              className="input"
              value={aliasesText}
              onChange={(e) => setAliasesText(e.target.value)}
              placeholder="Michel, Knoop, MK (kommagescheiden)"
              disabled={isSaving || savedOk}
            />
          </div>

          {/* Expertise / onderwerpen */}
          <div className="flex-col gap-4">
            <label
              style={{ fontSize: "var(--font-body)", fontWeight: 500, color: "var(--text-primary)" }}
            >
              Expertise / onderwerpen
            </label>
            <input
              type="text"
              className="input"
              value={expertiseText}
              onChange={(e) => setExpertiseText(e.target.value)}
              placeholder="grafisch ontwerp, marketing, IT (kommagescheiden)"
              disabled={isSaving || savedOk}
            />
          </div>

          {/* Intern / extern tri-state */}
          <div className="flex-col gap-4">
            <label
              style={{ fontSize: "var(--font-body)", fontWeight: 500, color: "var(--text-primary)" }}
            >
              Intern / extern
            </label>
            <select
              className="input"
              value={isInternalValue}
              onChange={(e) => setIsInternalValue(e.target.value as "true" | "false" | "null")}
              disabled={isSaving || savedOk}
            >
              <option value="null">Onbekend</option>
              <option value="true">Intern</option>
              <option value="false">Extern</option>
            </select>
          </div>
        </div>

        {/* Modal footer */}
        <div
          style={{
            padding: "16px 20px",
            borderTop: "1px solid var(--stroke-divider)",
            display: "flex",
            flexDirection: "column",
            gap: 8,
          }}
        >
          {/* Save error */}
          {saveError && (
            <p
              style={{
                fontSize: "var(--font-caption)",
                color: "var(--fill-system-critical)",
                margin: 0,
              }}
              role="alert"
            >
              {saveError}
            </p>
          )}

          {/* Save button */}
          <button
            className="btn btn-primary"
            onClick={handleSave}
            disabled={isSaving || savedOk}
            style={{ width: "100%", justifyContent: "center", gap: 8 }}
          >
            {savedOk ? (
              <>
                <Checkmark24Regular style={{ fontSize: 16 }} />
                Opgeslagen
              </>
            ) : isSaving ? (
              "Opslaan..."
            ) : (
              "Wijzigingen opslaan"
            )}
          </button>
        </div>
      </div>
    </DesktopDialog>
  );
}
