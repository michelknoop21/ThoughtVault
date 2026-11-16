// Profile choice for regenerating a notule. Local transcripts also get the detail level picker, preselected by the
// regenerate rule (DEC-073); the server's regenerate call takes no level, so cloud transcripts do not show it.
import { useState } from "react";
import { DesktopDialog } from "../ui/DesktopDialog";
import { DetailLevelPicker } from "../DetailLevelPicker";
import { useProfilesStore } from "../../stores/profilesStore";
import { useSettingsStore } from "../../stores/settingsStore";
import { isLocalId } from "../../stores/localTranscriptsStore";
import { regenerateDetailLevel } from "../../services/notuleDetailLevel";
import { enrichProfile } from "../../services/profileTemplates";
import type { NotuleDetailLevel, Transcript } from "../../types";

export function RegenerateDialog({ transcript, onCancel, onConfirm }: {
  transcript: Transcript;
  onCancel: () => void;
  /** `detailLevel` undefined: no level was offered (cloud transcript or a profile without a level). */
  onConfirm: (profileId: string, detailLevel?: NotuleDetailLevel) => void;
}) {
  const profiles = useProfilesStore((s) => s.profiles);
  const levelFor = (id: string) => {
    const profile = profiles.find((p) => p.id === id);
    return profile ? regenerateDetailLevel(transcript, enrichProfile(profile), useSettingsStore.getState().profile_detail_levels) : "volledig";
  };
  const [profileId, setProfileId] = useState(() =>
    profiles.find((p) => p.id === transcript.profile_id)?.id
      ?? profiles.find((p) => p.name === transcript.profile_name || p.id === transcript.profile_name)?.id ?? profiles[0]?.id ?? "");
  const [level, setLevel] = useState<NotuleDetailLevel>(() => levelFor(profileId));
  const selected = profiles.find((p) => p.id === profileId);
  const showLevel = isLocalId(transcript.id) && !!selected && !!enrichProfile(selected).detail_level;

  return (
    <DesktopDialog className="td-overlay" label="Notule opnieuw genereren" onClose={onCancel}>
      <div className="td-tags-dialog" onClick={(e) => e.stopPropagation()}>
        <h3 className="td-tags-title">Notulen regenereren</h3>
        <p className="text-caption">Kies het template voor de nieuwe notulen.</p>
        <select className="select" value={profileId}
          onChange={(e) => { setProfileId(e.target.value); setLevel(levelFor(e.target.value)); }}>
          {profiles.map((profile) => <option key={profile.id} value={profile.id}>{profile.name}</option>)}
        </select>
        {showLevel && <DetailLevelPicker value={level} onChange={setLevel} />}
        <div className="flex-row gap-8" style={{ justifyContent: "flex-end", marginTop: 16 }}>
          <button className="btn" onClick={onCancel}>Annuleren</button>
          <button className="btn btn-accent" onClick={() => onConfirm(profileId, showLevel ? level : undefined)}>Regenereren</button>
        </div>
      </div>
    </DesktopDialog>
  );
}
