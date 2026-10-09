import { expect, it } from "vitest";
import { studioLayout } from "../studioLayout";

it("matches the native studio landmarks at regular and short heights", () => {
  expect(studioLayout(930, 880)).toMatchObject({
    inset: 45, timerSize: 85, timerY: 208, listenY: 302,
    transportTop: 580, transportWidth: 164, barBottom: 37,
    waveTop: 342, waveHeight: 218,
  });
  expect(studioLayout(733, 705)).toMatchObject({
    inset: 45, timerSize: 64, timerY: 124, listenY: 196,
    transportTop: 450, barBottom: 20, waveTop: 236, waveHeight: 194,
  });
});

it("keeps the waveform between labels and transport across the native height breakpoint", () => {
  for (const height of [560, 600, 680, 705, 719, 720, 800, 880, 1080]) {
    for (const width of [300, 499, 500, 733, 930]) {
      const layout = studioLayout(width, height);
      expect(layout.waveTop).toBeGreaterThanOrEqual(layout.listenY + 40);
      expect(layout.waveTop + layout.waveHeight).toBeLessThanOrEqual(layout.transportTop - 20);
      expect(layout.waveHeight).toBeLessThanOrEqual(280);
      expect(layout.transportWidth * 3).toBeLessThanOrEqual(width - 2 * layout.inset);
    }
  }
});
