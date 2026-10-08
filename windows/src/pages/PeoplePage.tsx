import { useState } from "react";
import { Delete24Regular, PersonAdd24Regular, People24Regular } from "../components/ui/StudioIcons";
import { usePeopleDirectoryStore } from "../stores/peopleDirectoryStore";
import type { PersonProfile } from "../types";
import { PersonEditModal } from "./PersonEditModal";

export function PeoplePage() {
  const people = usePeopleDirectoryStore((s) => s.people);
  const removePerson = usePeopleDirectoryStore((s) => s.removePerson);
  const createDefaultPerson = usePeopleDirectoryStore((s) => s.createDefaultPerson);

  const [search, setSearch] = useState("");
  const [editingPerson, setEditingPerson] = useState<PersonProfile | null>(null);
  const [isModalOpen, setIsModalOpen] = useState(false);
  // Delete confirm: tracks which person's delete button is in confirm state
  const [deleteConfirmId, setDeleteConfirmId] = useState<string | null>(null);

  // Filter on name + aliases + emails (case-insensitive)
  const query = search.trim().toLowerCase();
  const filtered = query
    ? people.filter((p) =>
        p.name.toLowerCase().includes(query) ||
        p.aliases.some((a) => a.toLowerCase().includes(query)) ||
        p.emails.some((e) => e.toLowerCase().includes(query))
      )
    : people;

  function handleAddPerson() {
    const newPerson = createDefaultPerson();
    setEditingPerson(newPerson);
    setIsModalOpen(true);
  }

  function handleEditPerson(person: PersonProfile) {
    if (deleteConfirmId === person.id) return; // don't open edit when confirming delete
    setEditingPerson(person);
    setIsModalOpen(true);
  }

  function handleDeleteClick(e: React.MouseEvent, personId: string) {
    e.stopPropagation();
    setDeleteConfirmId(personId);
  }

  function handleDeleteConfirm(e: React.MouseEvent, personId: string) {
    e.stopPropagation();
    removePerson(personId);
    setDeleteConfirmId(null);
  }

  function handleDeleteCancel(e: React.MouseEvent) {
    e.stopPropagation();
    setDeleteConfirmId(null);
  }

  function handleModalClose() {
    setIsModalOpen(false);
    setEditingPerson(null);
  }

  function getStatusDot(isInternal: boolean | null): { color: string; label: string } {
    if (isInternal === true) return { color: "var(--fill-accent)", label: "Intern" };
    if (isInternal === false) return { color: "var(--text-accent)", label: "Extern" };
    return { color: "var(--text-tertiary)", label: "Onbekend" };
  }

  return (
    <div className="page-scroll desktop-page desktop-people">
      {/* Page header */}
      <div className="page-header">
        <h1 className="page-title-sm">Mensen</h1>
        <button
          className="btn btn-primary"
          onClick={handleAddPerson}
          title="Persoon toevoegen"
        >
          <PersonAdd24Regular style={{ fontSize: 16 }} />
          Persoon toevoegen
        </button>
      </div>

      {/* Page content */}
      <div className="page-content">
        <div className="page-content-narrow">

          {/* Search input */}
          <input
            type="search"
            className="input"
            placeholder="Zoeken..."
            value={search}
            onChange={(e) => { setSearch(e.target.value); setDeleteConfirmId(null); }}
            style={{ marginBottom: 16 }}
          />

          {/* Empty state — no people at all */}
          {people.length === 0 && (
            <div
              className="people-empty"
              style={{
                display: "flex",
                flexDirection: "column",
                alignItems: "center",
                gap: 12,
                padding: "48px 16px",
                textAlign: "center",
              }}
            >
              <People24Regular className="people-empty-icon" />
              <p style={{ font: "var(--type-subtitle)", color: "var(--text-primary)", margin: 0 }}>
                Nog geen personen toegevoegd
              </p>
              <p style={{ font: "var(--type-body)", color: "var(--text-secondary)", margin: 0, maxWidth: 420 }}>
                Voeg collega's en bekende externen toe zodat ThoughtVault actiepunten aan hen kan koppelen.
              </p>
              <button className="btn btn-primary" onClick={handleAddPerson}>
                Persoon toevoegen
              </button>
            </div>
          )}

          {/* Search empty state — people exist but no search matches */}
          {people.length > 0 && query && filtered.length === 0 && (
            <p style={{ color: "var(--text-secondary)", padding: "12px 0", margin: 0 }}>
              Geen resultaten voor '{search}'
            </p>
          )}

          {/* Person list */}
          {filtered.length > 0 && (
            <div className="settings-group">
              {filtered.map((person) => {
                const dot = getStatusDot(person.isInternal);
                const subtitle = [person.role, person.organization]
                  .filter(Boolean)
                  .join(" · ");
                const isConfirming = deleteConfirmId === person.id;

                return (
                  <div
                    key={person.id}
                    className="settings-row"
                    style={{ cursor: isConfirming ? "default" : "pointer", userSelect: "none" }}
                    onClick={() => !isConfirming && handleEditPerson(person)}
                  >
                    {/* Status dot */}
                    <span
                      title={dot.label}
                      style={{
                        display: "inline-block",
                        width: 8,
                        height: 8,
                        borderRadius: "50%",
                        background: dot.color,
                        flexShrink: 0,
                        marginRight: 10,
                        alignSelf: "center",
                      }}
                    />

                    {/* Name + subtitle */}
                    <div className="flex-1">
                      <p
                        style={{
                          font: "var(--type-body)",
                          fontWeight: 600,
                          color: "var(--text-primary)",
                          margin: 0,
                        }}
                      >
                        {person.name || <span style={{ color: "var(--text-tertiary)" }}>Naamloos</span>}
                      </p>
                      {subtitle && (
                        <p
                          style={{
                            fontSize: "var(--font-caption)",
                            color: "var(--text-secondary)",
                            margin: 0,
                          }}
                        >
                          {subtitle}
                        </p>
                      )}
                    </div>

                    {/* Inline delete confirm OR hover-reveal delete button */}
                    {isConfirming ? (
                      <div
                        style={{
                          display: "flex",
                          flexDirection: "column",
                          alignItems: "flex-end",
                          gap: 4,
                          flexShrink: 0,
                        }}
                        onClick={(e) => e.stopPropagation()}
                      >
                        <p
                          style={{
                            fontSize: "var(--font-caption)",
                            color: "var(--text-secondary)",
                            margin: 0,
                          }}
                        >
                          Weet je het zeker? Dit verwijdert {person.name || "deze persoon"} uit je directory.
                        </p>
                        <div style={{ display: "flex", gap: 8 }}>
                          <button
                            className="btn btn-sm"
                            style={{ color: "var(--fill-system-critical)" }}
                            onClick={(e) => handleDeleteConfirm(e, person.id)}
                          >
                            Verwijderen
                          </button>
                          <button
                            className="btn btn-secondary btn-sm"
                            onClick={handleDeleteCancel}
                          >
                            Annuleren
                          </button>
                        </div>
                      </div>
                    ) : (
                      <button
                        className="btn btn-ghost btn-sm person-row-delete"
                        aria-label={`Verwijder ${person.name}`}
                        title={`Verwijder ${person.name}`}
                        onClick={(e) => handleDeleteClick(e, person.id)}
                        style={{ opacity: 0, transition: "opacity 0.1s", flexShrink: 0 }}
                        onFocus={(e) => { (e.currentTarget as HTMLButtonElement).style.opacity = "1"; }}
                        onBlur={(e) => { (e.currentTarget as HTMLButtonElement).style.opacity = "0"; }}
                      >
                        <Delete24Regular style={{ fontSize: 16, color: "var(--fill-system-critical)" }} />
                      </button>
                    )}
                  </div>
                );
              })}
            </div>
          )}
        </div>
      </div>

      {/* Edit / Add modal */}
      {isModalOpen && editingPerson && (
        <PersonEditModal
          person={editingPerson}
          isNew={!people.some((p) => p.id === editingPerson.id)}
          onClose={handleModalClose}
        />
      )}

      {/* Hover-reveal delete button CSS */}
      <style>{`
        .settings-row:hover .person-row-delete {
          opacity: 1 !important;
        }
      `}</style>
    </div>
  );
}
