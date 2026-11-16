// One profile in the Profielen list. A bundled profile with a detail level shows the level picker.
import {
  Edit24Regular,
  Delete24Regular,
  Copy24Regular,
  Globe24Regular,
  LockClosed24Regular,
  Star24Regular,
  ProfileIcons,
} from "./ui/StudioIcons";
import { ProfileDetailLevelPicker } from "./DetailLevelPicker";
import profileTemplates from "../data/profileTemplates.json";
import type { Profile } from "../types";

export function ProfileCard({
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
  const template = profileTemplates.find((entry) => entry.id === profile.id);
  const Icon = template ? ProfileIcons[template.icon] : undefined;
  return (
    <div className="card-static profile-card">
      {/* Icon */}
      <span className="profile-card-icon">{Icon ? <Icon /> : profile.icon || "📄"}</span>

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
        {!showCopy && <ProfileDetailLevelPicker profile={profile} />}
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
