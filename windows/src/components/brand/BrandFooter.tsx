import { YingaLogo } from "./YingaLogo";

export function BrandFooter({ compact }: { compact?: boolean }) {
  return (
    <div className={`brand-footer${compact ? " brand-footer-compact" : ""}`}>
      <span className={compact ? "brand-footer-text-compact" : "brand-footer-text"}>Developed by</span>
      <YingaLogo height={compact ? 16 : 32} />
    </div>
  );
}
