// Kort / Normaal / Volledig picker with one explanation line per level (DEC-073). Used in the profile settings
// and in the regenerate dialog; same texts as macos/Views/DetailLevelPicker.swift.
import { useSettingsStore } from "../stores/settingsStore";
import { chooseDetailLevel, effectiveDetailLevel } from "../services/notuleDetailLevel";
import { enrichProfile } from "../services/profileTemplates";
import type { NotuleDetailLevel, Profile } from "../types";

const LEVELS: { id: NotuleDetailLevel; label: string; explanation: string }[] = [
  { id: "kort", label: "Kort", explanation: "Kort: besluiten, acties en bedragen; ongeveer 6% van het gesprek, 1.500 tot 4.000 tekens" },
  { id: "normaal", label: "Normaal", explanation: "Normaal: ook één of twee zinnen context per onderwerp; ongeveer 15%, 2.500 tot 8.000 tekens" },
  { id: "volledig", label: "Volledig", explanation: "Volledig: elke bronzin uit het gesprek komt terug, ook bijzaken" },
];

export function DetailLevelPicker({ value, onChange }: { value: NotuleDetailLevel; onChange: (level: NotuleDetailLevel) => void }) {
  return (
    <div className="detail-level-picker" style={{ display: "flex", flexDirection: "column", gap: 4, marginTop: 12 }}>
      <p className="text-caption" style={{ margin: 0, fontWeight: 600 }}>Detailniveau</p>
      <div className="action-row" role="group" aria-label="Detailniveau">
        {LEVELS.map((item) => (
          <button key={item.id} type="button" aria-pressed={value === item.id}
            className={`btn btn-sm ${value === item.id ? "btn-accent" : "btn-secondary"}`}
            onClick={() => onChange(item.id)}>{item.label}</button>
        ))}
      </div>
      {LEVELS.map((item) => (
        <p key={item.id} className="text-caption"
          style={{ margin: 0, color: value === item.id ? "var(--text-primary)" : "var(--text-tertiary)" }}>{item.explanation}</p>
      ))}
    </div>
  );
}

/** The picker bound to the user's choice for `profile` (settings profile_detail_levels); nothing for a profile without a level. */
export function ProfileDetailLevelPicker({ profile }: { profile: Profile }) {
  const choices = useSettingsStore((s) => s.profile_detail_levels) ?? {};
  const updateSettings = useSettingsStore((s) => s.updateSettings);
  const enriched = enrichProfile(profile);
  if (!enriched.detail_level) return null;
  return <DetailLevelPicker value={effectiveDetailLevel(enriched, choices)}
    onChange={(level) => updateSettings({ profile_detail_levels: chooseDetailLevel(choices, enriched, level) })} />;
}
