export type AudioLevelNormalizer = (rawLevel: number) => number;

/**
 * Converts raw RMS audio levels (0.0–1.0) to a stable 0–100 UI scale with:
 * - adaptive noise floor (suppresses hiss)
 * - adaptive peak tracking (visible dynamics on soft/hard speech)
 */
export function createAudioLevelNormalizer(): AudioLevelNormalizer {
  let noiseFloor = 0.01;
  let peak = 0.2;

  return (rawLevel: number): number => {
    const raw = Math.max(0, Math.min(1, rawLevel));

    // Track ambient floor mostly when signal is close to floor.
    if (raw < noiseFloor + 0.04) {
      noiseFloor = noiseFloor * 0.985 + raw * 0.015;
    } else {
      noiseFloor *= 0.998;
    }
    noiseFloor = Math.max(0.002, Math.min(0.08, noiseFloor));

    // Fast attack, slow release peak tracker.
    peak = Math.max(raw, peak * 0.992);
    peak = Math.max(peak, noiseFloor + 0.08);

    const normalized = (raw - noiseFloor) / (peak - noiseFloor);
    const clamped = Math.max(0, Math.min(1, normalized));

    // Expand visible dynamics in the mid/low range.
    const shaped = Math.pow(clamped, 0.52);
    return Math.max(0, Math.min(100, shaped * 100));
  };
}
