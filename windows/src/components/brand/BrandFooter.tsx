/**
 * "Developed by Yinga" footer for consistent branding.
 * Matches the macOS BrandFooter component.
 * compact: half-size version for use in the main app shell.
 */
export function BrandFooter({ compact }: { compact?: boolean }) {
  return (
    <div className={`brand-footer${compact ? " brand-footer-compact" : ""}`}>
      <span className={compact ? "brand-footer-text-compact" : "brand-footer-text"}>
        Developed by
      </span>
      <span
        className={compact ? "brand-footer-wordmark-compact" : "brand-footer-wordmark"}
      >
        Yinga
      </span>
    </div>
  );
}
