// Logical-point parity with macOS StudioLayout, independent of display scale.
export function studioLayout(width: number, height: number) {
  const narrow = width < 500;
  const low = height < 720;
  const inset = narrow ? 20 : 45;
  const transportY = height - (low ? 190 : 235);
  const waveTop = (low ? 196 : 302) + 40;
  const waveBottom = Math.max(waveTop, transportY - 85);
  const waveHeight = Math.min(280, waveBottom - waveTop);
  return {
    inset, trailingInset: narrow ? 20 : 32, barRight: narrow ? 20 : 38,
    pillTop: low ? 24 : 45, timerSize: low ? 64 : 85,
    timerY: low ? 124 : 208, listenY: low ? 196 : 302,
    transportTop: transportY - 65, transportWidth: Math.max(0, Math.min(164, (width - 2 * inset) / 3)),
    barBottom: low ? 20 : 37, waveTop: (waveTop + waveBottom - waveHeight) / 2, waveHeight,
  };
}
