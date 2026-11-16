import { useInRouterContext, useNavigate } from "react-router-dom";
import { OBSIDIAN_BROKEN_MESSAGE } from "../../services/obsidian";
import { useObsidianLinkStore } from "../../stores/obsidianStore";
import { useSettingsStore } from "../../stores/settingsStore";

/** Stable per mount: the router context does not change while a component is mounted. */
function useOpenObsidianSettings(): () => void {
  return useInRouterContext() ? (() => { const navigate = useNavigate(); return () => navigate("/settings?tab=obsidian"); })() : () => {};
}

/** The single message for a broken Obsidian link, shown in the notule view and on the Obsidian settings tab. */
export function ObsidianBrokenNotice({ onChooseVault }: { onChooseVault?: () => void }) {
  const broken = useObsidianLinkStore((s) => s.broken);
  const enabled = useSettingsStore((s) => s.obsidian_enabled);
  const openSettings = useOpenObsidianSettings();
  if (!enabled || !broken) return null;
  return (
    <div className="settings-row" role="alert" style={{ gap: 10, flexWrap: "wrap", alignItems: "center" }}>
      <p className="settings-desc" style={{ flex: 1, minWidth: 220 }}>{OBSIDIAN_BROKEN_MESSAGE}</p>
      <button className="btn btn-secondary btn-sm" onClick={onChooseVault ?? openSettings}>Vault opnieuw kiezen</button>
      <button className="btn btn-secondary btn-sm" onClick={() => {
        useSettingsStore.getState().updateSettings({ obsidian_enabled: false });
        useObsidianLinkStore.getState().setBroken(false);
      }}>Obsidian uitzetten</button>
    </div>
  );
}
