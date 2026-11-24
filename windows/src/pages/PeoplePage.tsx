import { useState } from "react";
import { Delete24Regular, Edit24Regular, PersonAdd24Regular, People24Regular } from "../components/ui/StudioIcons";
import { usePeopleDirectoryStore } from "../stores/peopleDirectoryStore";
import type { PersonProfile } from "../types";
import { PersonEditModal, initials } from "./PersonEditModal";

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

  function kind(isInternal: boolean | null): { className: string; label: string } {
    if (isInternal === true) return { className: "intern", label: "Intern" };
    if (isInternal === false) return { className: "extern", label: "Extern" };
    return { className: "unknown", label: "Onbekend" };
  }

  return (
    <div className="page-scroll desktop-page desktop-people">
      <div className="page-content people-wrap">
        {/* Page header */}
        <header className="people-head">
          <div className="people-head-title">
            <h1>Mensen</h1>
            {people.length > 0 && (
              <p>
                {people.length} {people.length === 1 ? "persoon" : "personen"}. ThoughtVault gebruikt deze lijst om namen goed te schrijven en actiepunten toe te wijzen.
              </p>
            )}
          </div>
          <input
            type="search"
            placeholder="Zoeken..."
            aria-label="Zoeken"
            value={search}
            onChange={(e) => { setSearch(e.target.value); setDeleteConfirmId(null); }}
            className="input people-toolbar-search"
          />
          <button
            className="btn btn-primary"
            onClick={handleAddPerson}
            title="Persoon toevoegen"
          >
            <PersonAdd24Regular style={{ fontSize: 16 }} />
            Persoon toevoegen
          </button>
        </header>

        {/* Empty state — no people at all */}
        {people.length === 0 && (
          <div className="people-empty">
            <People24Regular className="people-empty-icon" />
            <p className="people-empty-title">Nog geen personen toegevoegd</p>
            <p className="people-empty-body">
              Voeg collega's en bekende externen toe zodat ThoughtVault actiepunten aan hen kan koppelen.
            </p>
            <button className="btn btn-primary" onClick={handleAddPerson}>
              Persoon toevoegen
            </button>
          </div>
        )}

        {/* Search empty state — people exist but no search matches */}
        {people.length > 0 && query && filtered.length === 0 && (
          <p className="people-no-results">Geen resultaten voor '{search}'</p>
        )}

        {/* Person list */}
        {filtered.length > 0 && (
          <div className="people-card">
            <div className="people-row people-row-head" aria-hidden="true">
              <span /><span>Naam</span><span>Expertise</span><span>Soort</span><span />
            </div>
            {filtered.map((person) => {
              const k = kind(person.isInternal);
              const subtitle = [person.role, person.organization]
                .filter(Boolean)
                .join(" · ");
              const isConfirming = deleteConfirmId === person.id;
              const displayName = person.name || "Naamloos";

              return (
                <div
                  key={person.id}
                  className={`people-row${isConfirming ? " confirming" : ""}`}
                  onClick={() => !isConfirming && handleEditPerson(person)}
                >
                  <span className={`people-avatar ${k.className}`} aria-hidden="true">
                    {initials(person.name) || <People24Regular />}
                  </span>

                  {/* Name + subtitle */}
                  <div className="people-name">
                    <p>{person.name || <span className="people-muted">Naamloos</span>}</p>
                    {subtitle && <p className="people-sub">{subtitle}</p>}
                  </div>

                  <div className="people-tags">
                    {(person.expertiseTags ?? []).length > 0
                      ? person.expertiseTags.map((tag) => <span key={tag} className="people-tag">{tag}</span>)
                      : <span className="people-muted">Nog geen expertise</span>}
                  </div>

                  <div className="people-kind">
                    <span className={`people-chip ${k.className}`}>{k.label}</span>
                  </div>

                  <div className="people-actions">
                    <button
                      className="people-icon-btn"
                      aria-label={`${displayName} bewerken`}
                      title="Bewerken"
                      disabled={isConfirming}
                      onClick={(e) => { e.stopPropagation(); handleEditPerson(person); }}
                    >
                      <Edit24Regular />
                    </button>
                    <button
                      className="people-icon-btn danger"
                      aria-label={`Verwijder ${person.name}`} data-log-label="Persoon verwijderen"
                      title={`Verwijder ${person.name}`}
                      disabled={isConfirming}
                      onClick={(e) => handleDeleteClick(e, person.id)}
                    >
                      <Delete24Regular />
                    </button>
                  </div>

                  {/* Inline delete confirm */}
                  {isConfirming && (
                    <div className="people-confirm" onClick={(e) => e.stopPropagation()}>
                      <p>Weet je het zeker? Dit verwijdert {person.name || "deze persoon"} uit je directory.</p>
                      <div>
                        <button
                          className="btn btn-sm"
                          style={{ color: "var(--fill-system-critical)" }}
                          onClick={(e) => handleDeleteConfirm(e, person.id)}
                        >
                          Verwijderen
                        </button>
                        <button className="btn btn-secondary btn-sm" onClick={handleDeleteCancel}>
                          Annuleren
                        </button>
                      </div>
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        )}
      </div>

      {/* Edit / Add modal */}
      {isModalOpen && editingPerson && (
        <PersonEditModal
          person={editingPerson}
          isNew={!people.some((p) => p.id === editingPerson.id)}
          onClose={handleModalClose}
        />
      )}

    </div>
  );
}
