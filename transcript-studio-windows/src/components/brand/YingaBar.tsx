/**
 * Yinga four-color horizontal brand bar.
 * Matches the macOS YingaBar component exactly:
 * magenta #E50074, blue #007BC4, green #009F3C, orange #F39200.
 */
export function YingaBar({ height = 3 }: { height?: number }) {
  return (
    <div className="brand-bar" style={{ height }}>
      <div className="brand-bar-magenta" />
      <div className="brand-bar-blue" />
      <div className="brand-bar-green" />
      <div className="brand-bar-orange" />
    </div>
  );
}
