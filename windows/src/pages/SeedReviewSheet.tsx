import { DesktopDialog } from "../components/ui/DesktopDialog";
import { useState } from "react";
import { usePeopleDirectoryStore } from "../stores/peopleDirectoryStore";

interface SeedCandidate {
  email: string;
  checked: boolean;
}

interface SeedReviewSheetProps {
  candidates: string[];  // deduped attendee emails from newSeedCandidates()
  onClose: () => void;
}

export function SeedReviewSheet({ candidates, onClose }: SeedReviewSheetProps) {
  const addPerson = usePeopleDirectoryStore((s) => s.addPerson);
  const createDefaultPerson = usePeopleDirectoryStore((s) => s.createDefaultPerson);

  const [rows, setRows] = useState<SeedCandidate[]>(
    candidates.map((email) => ({ email, checked: true }))
  );

  const checkedCount = rows.filter((r) => r.checked).length;

  function toggleRow(index: number) {
    setRows((prev) =>
      prev.map((r, i) => (i === index ? { ...r, checked: !r.checked } : r))
    );
  }

  // Derive a display name from an email: split on separators and capitalize each word (matches macOS)
  function deriveDisplayName(email: string): string {
    const emailPrefix = email.split("@")[0] ?? email;
    return emailPrefix
      .split(/[._-]/)
      .map((s) => s.charAt(0).toUpperCase() + s.slice(1))
      .join(" ");
  }

  function handleConfirm() {
    // Add only checked candidates as new directory entries (isInternal:null = onbekend, D-09)
    for (const row of rows) {
      if (!row.checked) continue;
      const person = createDefaultPerson({
        name: deriveDisplayName(row.email),
        emails: [row.email],
      });
      addPerson(person);
    }
    onClose();
  }

  function handleSkip() {
    onClose();
  }

  // Pluralised button label
  const confirmLabel =
    checkedCount === 1
      ? "Voeg 1 persoon toe"
      : `Voeg ${checkedCount} personen toe`;

  return (
    /* Overlay backdrop */
    <DesktopDialog label="Deelnemers herkennen" onClose={onClose}>
      {/* Modal panel */}
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
        aria-label="Nieuwe deelnemers gevonden"
      >
        {/* Header */}
        <div style={{ padding: "20px 20px 12px" }}>
          <h2
            style={{
              font: "var(--type-subtitle)",
              color: "var(--text-primary)",
              margin: "0 0 6px",
            }}
          >
            Nieuwe deelnemers gevonden
          </h2>
          <p
            style={{
              font: "var(--type-body)",
              color: "var(--text-secondary)",
              margin: 0,
            }}
          >
            {candidates.length === 1
              ? "1 deelnemer uit je agenda staat nog niet in je directory."
              : `${candidates.length} deelnemers uit je agenda staan nog niet in je directory.`}
          </p>
        </div>

        {/* Scrollable person list */}
        <div style={{ overflowY: "auto", flex: 1, padding: "0 20px" }}>
          {rows.map((row, index) => {
            const displayName = deriveDisplayName(row.email);

            return (
              <label
                key={row.email}
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
                  checked={row.checked}
                  onChange={() => toggleRow(index)}
                  style={{ flexShrink: 0, width: 16, height: 16, cursor: "pointer" }}
                />
                <div>
                  <p
                    style={{
                      font: "var(--type-body)",
                      fontWeight: 500,
                      color: "var(--text-primary)",
                      margin: 0,
                    }}
                  >
                    {displayName}
                  </p>
                  <p
                    style={{
                      fontSize: "var(--font-caption)",
                      color: "var(--text-secondary)",
                      margin: 0,
                    }}
                  >
                    {row.email}
                  </p>
                </div>
              </label>
            );
          })}

          {/* Self-email footnote (D-10 edge-case acknowledgement) */}
          <p
            style={{
              fontSize: "var(--font-caption)",
              color: "var(--text-tertiary)",
              margin: "12px 0",
              lineHeight: 1.5,
            }}
          >
            Sta jij er zelf tussen? Vul je e-mailadres in je profiel in zodat je voortaan automatisch wordt overgeslagen.
          </p>
        </div>

        {/* Footer buttons */}
        <div
          style={{
            padding: "16px 20px",
            borderTop: "1px solid var(--stroke-divider)",
            display: "flex",
            gap: 10,
            justifyContent: "flex-end",
          }}
        >
          <button
            className="btn btn-ghost"
            onClick={handleSkip}
          >
            Overslaan
          </button>
          <button
            className="btn btn-primary"
            onClick={handleConfirm}
            disabled={checkedCount === 0}
          >
            {confirmLabel}
          </button>
        </div>
      </div>
    </DesktopDialog>
  );
}
