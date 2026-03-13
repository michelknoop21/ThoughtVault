import { YingaLogo } from "./YingaLogo";

/**
 * "Developed by [Yinga logo]" footer for consistent branding.
 * compact: half-size version for use in the main app shell.
 * Default (non-compact): full-size for login/onboarding screens.
 */
export function YingaFooter({ compact }: { compact?: boolean }) {
  return (
    <div className={`yinga-footer${compact ? " yinga-footer-compact" : ""}`}>
      <span className={compact ? "yinga-footer-text-compact" : "yinga-footer-text"}>
        Developed by
      </span>
      <YingaLogo height={compact ? 16 : 32} />
    </div>
  );
}
