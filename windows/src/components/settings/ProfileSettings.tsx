import { useState, useEffect } from "react";
import { usePersonProfileStore } from "../../stores/personProfileStore";

export function ProfileSettings() {
  const profile = usePersonProfileStore((s) => s.profile);
  const upsertProfile = usePersonProfileStore((s) => s.upsertProfile);

  const [name, setName] = useState(profile?.name ?? "");
  const [role, setRole] = useState(profile?.role ?? "");
  const [organization, setOrganization] = useState(profile?.organization ?? "");
  const [aliases, setAliases] = useState(profile?.aliases.join(", ") ?? "");
  const [meetingTypes, setMeetingTypes] = useState(
    profile?.meetingTypes.join(", ") ?? ""
  );
  const [expertiseTags, setExpertiseTags] = useState(
    profile?.expertiseTags.join(", ") ?? ""
  );

  const [isSaving, setIsSaving] = useState(false);
  const [savedMessage, setSavedMessage] = useState<string | null>(null);

  // Re-seed local state when profile changes externally (e.g. after onboarding)
  useEffect(() => {
    setName(profile?.name ?? "");
    setRole(profile?.role ?? "");
    setOrganization(profile?.organization ?? "");
    setAliases(profile?.aliases.join(", ") ?? "");
    setMeetingTypes(profile?.meetingTypes.join(", ") ?? "");
    setExpertiseTags(profile?.expertiseTags.join(", ") ?? "");
  }, [profile]);

  function handleSave() {
    setIsSaving(true);
    setSavedMessage(null);
    try {
      const splitTrim = (s: string) =>
        s
          .split(",")
          .map((v) => v.trim())
          .filter(Boolean);
      upsertProfile({
        name: name.trim(),
        role: role.trim(),
        organization: organization.trim(),
        aliases: splitTrim(aliases),
        meetingTypes: splitTrim(meetingTypes),
        expertiseTags: splitTrim(expertiseTags),
      });
      setSavedMessage("Opgeslagen");
      setTimeout(() => setSavedMessage(null), 2000);
    } catch {
      setSavedMessage("Kon profiel niet opslaan. Probeer het opnieuw.");
    } finally {
      setIsSaving(false);
    }
  }

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 12 }}>
      {/* Empty state notice */}
      {profile === null && (
        <div className="profile-empty">
          <p>Geen profiel ingevuld</p>
          <span>Vul je naam, rol en organisatie in zodat ThoughtVault actiepunten aan jou kan koppelen.</span>
        </div>
      )}

      {/* Form fields */}
      <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
        <ProfileFormField
          label="Naam"
          value={name}
          onChange={setName}
          placeholder="Voornaam Achternaam"
        />
        <ProfileFormField
          label="Rol / Functie"
          value={role}
          onChange={setRole}
          placeholder="Product Manager"
        />
        <ProfileFormField
          label="Organisatie"
          value={organization}
          onChange={setOrganization}
          placeholder="Bedrijfsnaam"
        />
        <ProfileFormField
          label="Hoe noemen collega's jou?"
          value={aliases}
          onChange={setAliases}
          placeholder="Michel, Knoop, MK (kommagescheiden)"
        />
        <ProfileFormField
          label="Typische vergadertypen"
          value={meetingTypes}
          onChange={setMeetingTypes}
          placeholder="Wekelijks overleg, Klantgesprek (kommagescheiden)"
        />
        <ProfileFormField
          label="Expertise / onderwerpen"
          value={expertiseTags}
          onChange={setExpertiseTags}
          placeholder="grafisch ontwerp, marketing, IT (kommagescheiden)"
        />
      </div>

      {/* Save button + feedback */}
      <div className="action-row">
        <button
          onClick={handleSave}
          disabled={isSaving}
          className="btn btn-accent btn-sm"
        >
          {isSaving ? "Opslaan..." : "Profiel opslaan"}
        </button>
        {savedMessage && (
          <span
            style={{
              fontSize: 12,
              color:
                savedMessage === "Opgeslagen"
                  ? "var(--text-secondary)"
                  : "var(--fill-system-critical)",
            }}
          >
            {savedMessage}
          </span>
        )}
      </div>
    </div>
  );
}

function ProfileFormField({
  label,
  value,
  onChange,
  placeholder,
}: {
  label: string;
  value: string;
  onChange: (v: string) => void;
  placeholder?: string;
}) {
  return (
    <div className="form-field">
      <label className="form-label-sm">{label}</label>
      <input
        type="text"
        className="input"
        value={value}
        onChange={(e) => onChange(e.target.value)}
        placeholder={placeholder}
      />
    </div>
  );
}
