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
import { useProfilesStore } from "../stores/profilesStore";
import { api } from "../services/api";
import { useToast } from "../components/ui/InfoBar";
import type { Profile } from "../types";
import { DEFAULT_PROFILES } from "../types";

// Empty form state for create modal
const emptyForm = {
  name: "",
  description: "",
  icon: "",
  system_prompt: "",
  notule_prompt: "",
  notule_template: "",
};

export function ProfilesPage() {
  const { profiles, addProfile, updateProfile, deleteProfile, setProfiles } = useProfilesStore();
  const toast = useToast();

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

  // Load profiles from server on mount
  useEffect(() => {
    api.getProfiles().then((serverProfiles) => {
      if (serverProfiles.length > 0) {
        setProfiles(serverProfiles);
      }
    });
  }, [setProfiles]);

  function openCreate() {
    setEditingProfile(null);
    setForm(emptyForm);
    setShowModal(true);
  }

  function openEdit(profile: Profile) {
    setEditingProfile(profile);
    setForm({
      name: profile.name || "",
      description: profile.description || "",
      icon: profile.icon || "",
      system_prompt: profile.system_prompt || "",
      notule_prompt: profile.notule_prompt || "",
      notule_template: profile.notule_template || "",
    });
    setShowModal(true);
  }

  async function handleSave() {
    if (!form.name.trim()) {
      toast.show("Naam is verplicht", "error");
      return;
    }

    setLoading(true);
    try {
      if (editingProfile) {
        // Update existing
        const updates: Partial<Profile> = {
          name: form.name,
          description: form.description || undefined,
          icon: form.icon || undefined,
          system_prompt: form.system_prompt || undefined,
          notule_prompt: form.notule_prompt || undefined,
          notule_template: form.notule_template || undefined,
        };
        await api.updateProfile(editingProfile.id, updates);
        updateProfile(editingProfile.id, updates);
        toast.show("Profiel bijgewerkt", "success");
      } else {
        // Create new
        const created = await api.createProfile({
          name: form.name,
          description: form.description || undefined,
          icon: form.icon || undefined,
          system_prompt: form.system_prompt || undefined,
          notule_prompt: form.notule_prompt || undefined,
          notule_template: form.notule_template || undefined,
        });
        addProfile(created);
        toast.show("Profiel aangemaakt", "success");
      }
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
      await api.deleteProfile(id);
      deleteProfile(id);
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

  async function handleSetDefault(profile: Profile) {
    // Clear previous default, set new one
    profiles.forEach((p) => {
      if (p.is_default || p.isDefault) {
        updateProfile(p.id, { is_default: false, isDefault: false });
      }
    });
    updateProfile(profile.id, { is_default: true, isDefault: true });
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
    <div className="page-scroll">
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
                  isDefault={profile.is_default || profile.isDefault}
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
                    isDefault={profile.is_default || profile.isDefault}
                    onEdit={() => openEdit(profile)}
                    onDelete={() => setDeleteConfirm(profile.id)}
                    onToggleVisibility={() => handleToggleVisibility(profile)}
                    onSetDefault={() => handleSetDefault(profile)}
                  />
                ))
              )}
            </div>
          </div>

          {/* Browse publieke profielen */}
          <div className="settings-group">
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
          </div>

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
                  placeholder="Bijv. Brainstorm sessie"
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
                <div className="profile-prompt-header">
                  <label className="form-label">Systeem prompt</label>
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
                  placeholder="Instructies voor het AI model..."
                  style={{ resize: "vertical" }}
                />
              </div>
              <div className="form-field">
                <label className="form-label">Notule prompt</label>
                <textarea
                  className="input"
                  value={form.notule_prompt}
                  onChange={(e) => setForm({ ...form, notule_prompt: e.target.value })}
                  rows={3}
                  placeholder="Instructies voor notulengeneratie..."
                  style={{ resize: "vertical" }}
                />
              </div>
              <div className="form-field">
                <label className="form-label">Template</label>
                <textarea
                  className="input"
                  value={form.notule_template}
                  onChange={(e) => setForm({ ...form, notule_template: e.target.value })}
                  rows={3}
                  placeholder="HTML template voor de notulen..."
                  style={{ resize: "vertical" }}
                />
              </div>
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
