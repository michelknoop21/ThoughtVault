import yingaLogo from "../../assets/yinga-logo.svg";

export function BrandFooter({ compact }: { compact?: boolean }) {
  return <div className={`brand-footer${compact ? " brand-footer-compact" : ""}`}>
    <span className={compact ? "brand-footer-text-compact" : "brand-footer-text"}>Developed by</span>
    <img src={yingaLogo} alt="Yinga" className="brand-footer-logo" width="42" height="18" />
  </div>;
}
