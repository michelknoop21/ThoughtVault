/**
 * ThoughtVault brand bar: the logo's lavender to violet to indigo gradient.
 * Matches the macOS BrandBar component.
 */
export function BrandBar({ height = 3 }: { height?: number }) {
  return <div className="brand-bar" style={{ height }} />;
}
