import { DesktopDialog } from "../components/ui/DesktopDialog";
import { usePeopleDirectoryStore } from "../stores/peopleDirectoryStore";
import { useRecordingStore } from "../stores/recordingStore";

interface ParticipantPickerProps {
  onClose: () => void;
}

/**
 * Multi-select picker over the people directory. Marks who is in an ad-hoc meeting
 * (no calendar link) so the recording still carries a deelnemerslijst into the notule
 * pipeline. Calendar attendees are resolved automatically at upload; this only adds
 * manual picks on top. Binds directly to recordingStore.selectedParticipantIds.
 */
export function ParticipantPicker({ onClose }: ParticipantPickerProps) {
  const people = usePeopleDirectoryStore((s) => s.people);
  const selectedIds = useRecordingStore((s) => s.selectedParticipantIds);
  const setSelectedIds = useRecordingStore((s) => s.setSelectedParticipantIds);

  const selected = new Set(selectedIds);

  function toggle(id: string) {
    const next = new Set(selected);
    if (next.has(id)) next.delete(id);
    else next.add(id);
    setSelectedIds([...next]);
  }

  return (
    <DesktopDialog label="Deelnemers kiezen" onClose={onClose}>
      <div
        style={{
          background: "var(--surface-primary)",
          borderRadius: "var(--radius-md)",
          border: "1px solid var(--stroke-card)",
          width: "100%",
          maxWidth: 440,
          maxHeight: "85vh",
          display: "flex",
          flexDirection: "column",
          overflow: "hidden",
        }}
        role="dialog"
        aria-modal="true"
        aria-label="Deelnemers kiezen"
      >
        <div style={{ padding: "20px 20px 12px" }}>
          <h2 style={{ font: "var(--type-subtitle)", color: "var(--text-primary)", margin: "0 0 6px" }}>
            Deelnemers kiezen
          </h2>
          <p style={{ font: "var(--type-body)", color: "var(--text-secondary)", margin: 0 }}>
            Selecteer wie aanwezig is. Deze namen komen in de notule en acties kunnen aan hen worden gekoppeld.
          </p>
        </div>

        <div style={{ overflowY: "auto", flex: 1, padding: "0 20px" }}>
          {people.length === 0 ? (
            <p style={{ font: "var(--type-body)", color: "var(--text-secondary)", margin: "16px 0" }}>
              Nog geen personen in de directory. Voeg eerst mensen toe via Mensen.
            </p>
          ) : (
            people.map((person) => {
              const isOn = selected.has(person.id);
              const subtitle = [person.role, person.organization].filter(Boolean).join(" · ");
              return (
                <label
                  key={person.id}
                  style={{
                    display: "flex",
                    alignItems: "center",
                    gap: 12,
                    padding: "10px 0",
                    borderBottom: "1px solid var(--stroke-divider)",
                    cursor: "pointer",
                    userSelect: "none",
                  }}
                >
                  <input
                    type="checkbox"
                    checked={isOn}
                    onChange={() => toggle(person.id)}
                    style={{ flexShrink: 0, width: 16, height: 16, cursor: "pointer" }}
                  />
                  <div>
                    <p style={{ font: "var(--type-body)", fontWeight: 500, color: "var(--text-primary)", margin: 0 }}>
                      {person.name || "Naamloos"}
                    </p>
                    {subtitle && (
                      <p style={{ fontSize: "var(--font-caption)", color: "var(--text-secondary)", margin: 0 }}>
                        {subtitle}
                      </p>
                    )}
                  </div>
                </label>
              );
            })
          )}
        </div>

        <div
          style={{
            padding: "16px 20px",
            borderTop: "1px solid var(--stroke-divider)",
            display: "flex",
            justifyContent: "flex-end",
          }}
        >
          <button className="btn btn-primary" onClick={onClose}>
            Gereed
          </button>
        </div>
      </div>
    </DesktopDialog>
  );
}
