import { ProfileEditForm, STIJLEN, DEFAULT_SYSTEM_PROMPT, emptyForm } from "../components/ProfileEditForm";
import { DesktopDialog } from "../components/ui/DesktopDialog";
import { useState, useEffect } from "react";
import { Add24Regular, Globe24Regular } from "../components/ui/StudioIcons";
import { ProfileCard } from "../components/ProfileCard";
import { currentProfileChoices, useProfilesStore } from "../stores/profilesStore";
import { api } from "../services/api";
import { saveProfileForMode, deleteProfileForMode } from "../services/profileActions";
import { useSettingsStore } from "../stores/settingsStore";
import { useRecordingStore } from "../stores/recordingStore";
import { useToast } from "../components/ui/InfoBar";
import type { Profile } from "../types";
import { DEFAULT_PROFILES } from "../types";

export function ProfilesPage({ embedded = false }: { embedded?: boolean }) {
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
    <div className={embedded ? "desktop-profiles embedded-profiles" : "page-scroll desktop-page desktop-profiles"}>
      {!embedded && <div className="page-header"><h1 className="page-title-sm">Profielen</h1></div>}

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
        <ModalOverlay label={editingProfile ? "Profiel bewerken" : "Nieuw profiel"} onClose={() => setShowModal(false)}>
          <ProfileEditForm editing={!!editingProfile} form={form} setForm={setForm}
            loading={loading} onClose={() => setShowModal(false)} onSave={handleSave} />
        </ModalOverlay>
      )}

      {/* Delete confirmation */}
      {deleteConfirm && (
        <ModalOverlay label="Profiel verwijderen" onClose={() => setDeleteConfirm(null)}>
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

function ModalOverlay({ children, label, onClose }: { children: React.ReactNode; label: string; onClose: () => void }) {
  return <DesktopDialog label={label} onClose={onClose}>{children}</DesktopDialog>;
}
