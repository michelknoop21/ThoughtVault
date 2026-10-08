import { useState, useEffect } from "react";
import {
  Add24Regular,
  Edit24Regular,
  Delete24Regular,
  Copy24Regular,
  Globe24Regular,
  LockClosed24Regular,
  Star24Regular,
} from "@fluentui/react-icons";
import { currentProfileChoices, useProfilesStore } from "../stores/profilesStore";
import { api } from "../services/api";
import { saveProfileForMode, deleteProfileForMode } from "../services/profileActions";
import { useSettingsStore } from "../stores/settingsStore";
import { useRecordingStore } from "../stores/recordingStore";
import { useToast } from "../components/ui/InfoBar";
import type { Profile } from "../types";
import { DEFAULT_PROFILES } from "../types";

const STIJLEN = [
  {
    id: "zakelijk",
    label: "Zakelijk",
    description: "Formele toon, geschikt voor directie en management",
    system_prompt: "Je bent een professionele notulist die zakelijke vergaderingen nauwkeurig en beknopt samenvat.",
  },
  {
    id: "informeel",
    label: "Informeel",
    description: "Vlotte, leesbare toon voor team-overleggen",
    system_prompt: "Je bent een vriendelijke assistent die gesprekken in begrijpelijke taal samenvat.",
  },
  {
    id: "technisch",
    label: "Technisch",
    description: "Technisch jargon, focus op architectuur en code",
    system_prompt: "Je bent een technische notulist gespecialiseerd in software ontwikkeling en IT-projecten.",
  },
] as const;

const DEFAULT_SYSTEM_PROMPT = STIJLEN[0].system_prompt;

// Empty form state for create modal
const emptyForm = {
  name: "",
  description: "",
  icon: "",
  stijl: "zakelijk" as string,
  system_prompt: "",
  notule_prompt: "",
  notule_template: "",
  sections: "",
};

export function ProfilesPage() {
  const { profiles, addProfile, updateProfile, setProfiles, showLocalProfiles } = useProfilesStore();
  const toast = useToast();
  const processingMode = useSettingsStore((state) => state.processing_mode);
  const defaultProfileId = useSettingsStore((state) => state.default_profile_id);
  const updateSettings = useSettingsStore((state) => state.updateSettings);
  const setSelectedProfileId = useRecordingStore((state) => state.setSelectedProfileId);

  const [showModal, setShowModal] = useState(false);
  const [editingProfile, setEditingProfile] = useState<Profile | null>(null);
  const [form, setForm] = useState(emptyForm);
  const [deleteConfirm, setDeleteConfirm] = useState<string | null>(null);
  const [publicProfiles, setPublicProfiles] = useState<Profile[]>([]);
  const [showPublic, setShowPublic] = useState(false);
  const [loading, setLoading] = useState(false);

  // Separate default (system) profiles from user's own
  const defaultProfileIds = new Set(DEFAULT_PROFILES.map((p) => p.id));
  const defaultProfiles = profiles.filter((p) => defaultProfileIds.has(p.id));
  const myProfiles = profiles.filter((p) => !defaultProfileIds.has(p.id));

  useEffect(() => {
    if (processingMode === "local") {
      showLocalProfiles();
      return;
    }
    let cancelled = false;
    api.getProfiles().then((serverProfiles) => {
      if (!cancelled) setProfiles(currentProfileChoices(serverProfiles));
    });
    return () => { cancelled = true; };
  }, [processingMode, setProfiles, showLocalProfiles]);

  function openCreate() {
    setEditingProfile(null);
    setForm(emptyForm);
    setShowModal(true);
  }

  function openEdit(profile: Profile) {
    setEditingProfile(profile);
    const matchedStijl = STIJLEN.find((s) => s.system_prompt === profile.system_prompt);
    setForm({
      name: profile.name || "",
      description: profile.description || "",
      icon: profile.icon || "",
      stijl: matchedStijl?.id || "zakelijk",
      system_prompt: matchedStijl ? "" : (profile.system_prompt || ""),
      notule_prompt: profile.notule_prompt || "",
      notule_template: profile.notule_template || profile.output_template || "",
      sections: (profile.output_template || profile.notule_template || "").includes("[Brongebonden inhoud]")
        ? [...(profile.output_template || profile.notule_template || "").matchAll(/<h2>([^<]+)<\/h2>/g)].map((match) => match[1]).join(", ")
        : "",
    });
    setShowModal(true);
  }

  async function handleSave() {
    if (!form.name.trim() || !form.notule_prompt.trim()) {
      toast.show("Naam en instructie zijn verplicht", "error");
      return;
    }

    setLoading(true);
    try {
      const stijlPrompt = STIJLEN.find((s) => s.id === form.stijl)?.system_prompt || DEFAULT_SYSTEM_PROMPT;
      const sectionList = form.sections.split(",").map((part) => part.trim()).filter(Boolean);
      const escapeHtml = (value: string) => value.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
      const sectionTemplate = sectionList.length
        ? `<h1>[Titel]</h1>\n${sectionList.map((name) => `<section><h2>${escapeHtml(name)}</h2><p>[Brongebonden inhoud]</p></section>`).join("\n")}`
        : undefined;
      const profile: Profile = {
        id: editingProfile?.id ?? crypto.randomUUID(),
        name: form.name.trim(),
        description: form.description || undefined,
        icon: form.icon || undefined,
        system_prompt: form.system_prompt.trim() || stijlPrompt,
        notule_prompt: form.notule_prompt.trim(),
        output_template: sectionTemplate ?? (form.notule_template.includes("[Brongebonden inhoud]") ? "" : form.notule_template.trim()),
        is_default: false,
      };
      await saveProfileForMode(processingMode, profile, Boolean(editingProfile));
      toast.show(editingProfile ? "Profiel bijgewerkt" : "Profiel aangemaakt", "success");
      setShowModal(false);
    } catch (err) {
      toast.show(err instanceof Error ? err.message : "Fout bij opslaan", "error");
    } finally {
      setLoading(false);
    }
  }

  async function handleDelete(id: string) {
    setLoading(true);
    try {
      await deleteProfileForMode(processingMode, id);
      toast.show("Profiel verwijderd", "success");
    } catch (err) {
      toast.show(err instanceof Error ? err.message : "Fout bij verwijderen", "error");
    } finally {
      setLoading(false);
      setDeleteConfirm(null);
    }
  }

  async function handleToggleVisibility(profile: Profile) {
    const newVisibility = !profile.isPublic;
    try {
      await api.setProfileVisibility(profile.id, newVisibility);
      updateProfile(profile.id, { isPublic: newVisibility });
      toast.show(newVisibility ? "Profiel is nu publiek" : "Profiel is nu prive", "success");
    } catch (err) {
      toast.show(err instanceof Error ? err.message : "Fout bij wijzigen zichtbaarheid", "error");
    }
  }

  function handleSetDefault(profile: Profile) {
    updateSettings({ default_profile_id: profile.id });
    setSelectedProfileId(profile.id);
    toast.show(`"${profile.name}" ingesteld als standaard`, "success");
  }

  async function loadPublicProfiles() {
    setShowPublic(true);
    try {
      const result = await api.getPublicProfiles();
      setPublicProfiles(result);
    } catch (err) {
      toast.show("Kon publieke profielen niet laden", "error");
    }
  }

  async function handleCopyProfile(profile: Profile) {
    try {
      const copied = await api.copyProfile(profile.id);
      addProfile(copied);
      toast.show(`"${profile.name}" gekopieerd naar mijn profielen`, "success");
    } catch (err) {
      toast.show(err instanceof Error ? err.message : "Fout bij kopieren", "error");
    }
  }

  return (
    <div className="page-scroll desktop-page desktop-profiles">
      <div className="page-header">
        <h1 className="page-title-sm">Profielen</h1>
      </div>

      <div className="page-content">
        <div className="page-content-narrow">

          {/* Standaard profielen */}
          <div className="settings-group">
            <p className="settings-group-label">Standaard profielen</p>
            <div className="profile-list">
              {defaultProfiles.map((profile) => (
                <ProfileCard
                  key={profile.id}
                  profile={profile}
                  readOnly
                  isDefault={defaultProfileId === profile.id}
                  onSetDefault={() => handleSetDefault(profile)}
                />
              ))}
            </div>
          </div>

          {/* Mijn profielen */}
          <div className="settings-group">
            <div className="profile-section-header">
              <p className="settings-group-label" style={{ margin: 0 }}>Mijn profielen</p>
              <button onClick={openCreate} className="btn btn-accent btn-sm">
                <Add24Regular style={{ fontSize: 14 }} />
                Nieuw profiel
              </button>
            </div>
            <div className="profile-list">
              {myProfiles.length === 0 ? (
                <p className="text-caption profile-empty">
                  Je hebt nog geen eigen profielen. Maak er een aan of kopieer een publiek profiel.
                </p>
              ) : (
                myProfiles.map((profile) => (
                  <ProfileCard
                    key={profile.id}
                    profile={profile}
                    isDefault={defaultProfileId === profile.id}
                    onEdit={() => openEdit(profile)}
                    onDelete={() => setDeleteConfirm(profile.id)}
                    onToggleVisibility={processingMode === "cloud" ? () => handleToggleVisibility(profile) : undefined}
                    onSetDefault={() => handleSetDefault(profile)}
                  />
                ))
              )}
            </div>
          </div>

          {/* Browse publieke profielen */}
          {processingMode === "cloud" && <div className="settings-group">
            <p className="settings-group-label">Community</p>
            <div className="profile-list">
              {!showPublic ? (
                <button onClick={loadPublicProfiles} className="btn btn-secondary btn-sm">
                  <Globe24Regular style={{ fontSize: 14 }} />
                  Browse publieke profielen
                </button>
              ) : (
                <>
                  {publicProfiles.length === 0 ? (
                    <p className="text-caption">Geen publieke profielen gevonden.</p>
                  ) : (
                    publicProfiles.map((profile) => (
                      <ProfileCard
                        key={profile.id}
                        profile={profile}
                        readOnly
                        showCopy
                        onCopy={() => handleCopyProfile(profile)}
                      />
                    ))
                  )}
                </>
              )}
            </div>
          </div>}

        </div>
      </div>

      {/* Create/Edit Modal */}
      {showModal && (
        <ModalOverlay onClose={() => setShowModal(false)}>
          <div className="card profile-modal">
            <p className="text-body-strong profile-modal-title">
              {editingProfile ? "Profiel bewerken" : "Nieuw profiel"}
            </p>
            <div className="flex-col gap-10">
              <div className="form-field">
                <label className="form-label">Naam</label>
                <input
                  className="input"
                  value={form.name}
                  onChange={(e) => setForm({ ...form, name: e.target.value })}
                  placeholder="Bijv. Brainstorm, Standup, Klantgesprek"
                />
              </div>
              <div className="form-field">
                <label className="form-label">Beschrijving</label>
                <input
                  className="input"
                  value={form.description}
                  onChange={(e) => setForm({ ...form, description: e.target.value })}
                  placeholder="Korte omschrijving van dit profiel"
                />
              </div>
              <div className="form-field">
                <label className="form-label">Icoon (emoji)</label>
                <input
                  className="input"
                  value={form.icon}
                  onChange={(e) => setForm({ ...form, icon: e.target.value })}
                  placeholder="Bijv. 📝"
                  style={{ width: 80 }}
                />
              </div>
              <div className="form-field">
                <label className="form-label">Stijl</label>
                <div style={{ display: "flex", gap: 8 }}>
                  {STIJLEN.map((stijl) => (
                    <button
                      key={stijl.id}
                      type="button"
                      onClick={() => setForm({ ...form, stijl: stijl.id })}
                      className="card-static"
                      style={{
                        flex: 1,
                        padding: "10px 8px",
                        textAlign: "center",
                        cursor: "pointer",
                        border: form.stijl === stijl.id ? "1.5px solid var(--fill-accent)" : "1px solid var(--stroke-default)",
                        background: form.stijl === stijl.id ? "var(--fill-accent-subtle)" : "var(--bg-card)",
                        borderRadius: 8,
                      }}
                    >
                      <p style={{ margin: 0, fontWeight: 600, fontSize: 13, color: form.stijl === stijl.id ? "var(--fill-accent)" : "var(--text-primary)" }}>
                        {stijl.label}
                      </p>
                      <p className="text-caption" style={{ margin: "4px 0 0", color: "var(--text-tertiary)" }}>
                        {stijl.description}
                      </p>
                    </button>
                  ))}
                </div>
                <p className="text-caption" style={{ marginTop: 4, color: "var(--text-tertiary)" }}>
                  Bepaalt de toon en schrijfstijl van de notulen.
                </p>
              </div>
              <div className="form-field">
                <label className="form-label">Wat moet er in de notulen staan?</label>
                <textarea
                  className="input"
                  value={form.notule_prompt}
                  onChange={(e) => setForm({ ...form, notule_prompt: e.target.value })}
                  rows={4}
                  placeholder="Bijv: Maak een beknopte samenvatting met actiepunten en besluiten. Gebruik een informele toon."
                  style={{ resize: "vertical" }}
                />
                <p className="text-caption" style={{ marginTop: 4, color: "var(--text-tertiary)" }}>
                  Beschrijf in je eigen woorden wat de AI moet doen: welke onderdelen, gewenste toon, en hoeveel detail.
                </p>
              </div>
              <div className="form-field">
                <label className="form-label">Secties (optioneel, gescheiden door komma&apos;s)</label>
                <input className="input" value={form.sections}
                  onChange={(e) => setForm({ ...form, sections: e.target.value })}
                  placeholder="Bijv. Onderwerpen, Acties, Open vragen" />
              </div>
              <details className="profile-advanced-section">
                <summary className="text-caption" style={{ cursor: "pointer", color: "var(--text-secondary)", userSelect: "none" }}>
                  Geavanceerde opties
                </summary>
                <div className="flex-col gap-10" style={{ marginTop: 10 }}>
                  <div className="form-field">
                    <div className="profile-prompt-header">
                      <label className="form-label">Rol van de AI</label>
                      <span className="text-caption" style={{ color: form.system_prompt.length > 4500 ? "var(--fill-system-critical)" : "var(--text-tertiary)" }}>
                        {form.system_prompt.length}/5000
                      </span>
                    </div>
                    <textarea
                      className="input"
                      value={form.system_prompt}
                      onChange={(e) => {
                        if (e.target.value.length <= 5000) {
                          setForm({ ...form, system_prompt: e.target.value });
                        }
                      }}
                      rows={3}
                      placeholder="Laat leeg voor de standaard rol. Vul in voor een specifieke persoonlijkheid of expertise."
                      style={{ resize: "vertical" }}
                    />
                  </div>
                  <div className="form-field">
                    <label className="form-label">HTML-sjabloon</label>
                    <textarea
                      className="input"
                      value={form.notule_template}
                      onChange={(e) => setForm({ ...form, notule_template: e.target.value })}
                      rows={3}
                      placeholder="Optioneel. Laat leeg voor de standaard opmaak."
                      style={{ resize: "vertical" }}
                    />
                  </div>
                </div>
              </details>
            </div>
            <div className="profile-modal-actions">
              <button onClick={() => setShowModal(false)} className="btn btn-secondary btn-sm">
                Annuleren
              </button>
              <button onClick={handleSave} disabled={loading} className="btn btn-accent btn-sm">
                {loading ? "Opslaan..." : "Opslaan"}
              </button>
            </div>
          </div>
        </ModalOverlay>
      )}

      {/* Delete confirmation */}
      {deleteConfirm && (
        <ModalOverlay onClose={() => setDeleteConfirm(null)}>
          <div className="card profile-modal-confirm">
            <p className="text-body-strong" style={{ marginBottom: 8 }}>Profiel verwijderen?</p>
            <p className="text-caption" style={{ marginBottom: 16 }}>
              Dit kan niet ongedaan worden gemaakt.
            </p>
            <div className="profile-modal-actions">
              <button onClick={() => setDeleteConfirm(null)} className="btn btn-secondary btn-sm">
                Annuleren
              </button>
              <button
                onClick={() => handleDelete(deleteConfirm)}
                disabled={loading}
                className="btn btn-sm"
                style={{ color: "var(--text-error)", borderColor: "rgba(188,0,22,0.3)" }}
              >
                {loading ? "Verwijderen..." : "Verwijderen"}
              </button>
            </div>
          </div>
        </ModalOverlay>
      )}
    </div>
  );
}

// Profile card component
function ProfileCard({
  profile,
  readOnly,
  isDefault,
  showCopy,
  onEdit,
  onDelete,
  onToggleVisibility,
  onSetDefault,
  onCopy,
}: {
  profile: Profile;
  readOnly?: boolean;
  isDefault?: boolean;
  showCopy?: boolean;
  onEdit?: () => void;
  onDelete?: () => void;
  onToggleVisibility?: () => void;
  onSetDefault?: () => void;
  onCopy?: () => void;
}) {
  return (
    <div className="card-static profile-card">
      {/* Icon */}
      <span className="profile-card-icon">{profile.icon || "📄"}</span>

      {/* Name + description */}
      <div className="profile-card-info">
        <div className="profile-card-name-row">
          <p className="text-body-strong truncate" style={{ margin: 0 }}>{profile.name}</p>
          {isDefault && (
            <span className="status-badge-accent profile-badge">Standaard</span>
          )}
          {profile.isPublic && (
            <Globe24Regular style={{ fontSize: 12, color: "var(--text-tertiary)", flexShrink: 0 }} />
          )}
        </div>
        {profile.description && (
          <p className="text-caption" style={{ margin: 0 }}>{profile.description}</p>
        )}
      </div>

      {/* Actions */}
      <div className="profile-card-actions">
        {showCopy && onCopy && (
          <button onClick={onCopy} className="icon-btn icon-btn-sm" title="Kopieer naar mijn profielen">
            <Copy24Regular style={{ fontSize: 16 }} />
          </button>
        )}
        {!readOnly && (
          <>
            {onSetDefault && !isDefault && (
              <button onClick={onSetDefault} className="icon-btn icon-btn-sm" title="Instellen als standaard">
                <Star24Regular style={{ fontSize: 16 }} />
              </button>
            )}
            {onToggleVisibility && (
              <button onClick={onToggleVisibility} className="icon-btn icon-btn-sm" title={profile.isPublic ? "Maak prive" : "Maak publiek"}>
                {profile.isPublic ? <LockClosed24Regular style={{ fontSize: 16 }} /> : <Globe24Regular style={{ fontSize: 16 }} />}
              </button>
            )}
            {onEdit && (
              <button onClick={onEdit} className="icon-btn icon-btn-sm" title="Bewerken">
                <Edit24Regular style={{ fontSize: 16 }} />
              </button>
            )}
            {onDelete && (
              <button onClick={onDelete} className="icon-btn icon-btn-sm icon-btn-danger" title="Verwijderen">
                <Delete24Regular style={{ fontSize: 16 }} />
              </button>
            )}
          </>
        )}
        {readOnly && !showCopy && onSetDefault && !isDefault && (
          <button onClick={onSetDefault} className="icon-btn icon-btn-sm" title="Instellen als standaard">
            <Star24Regular style={{ fontSize: 16 }} />
          </button>
        )}
      </div>
    </div>
  );
}

// Simple modal overlay
function ModalOverlay({ children, onClose }: { children: React.ReactNode; onClose: () => void }) {
  return (
    <div
      className="profile-overlay"
      onClick={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
    >
      {children}
    </div>
  );
}
