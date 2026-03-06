import { useEffect, useRef } from "react";

interface WaveformVisualizerProps {
  /** Audio level values in range 0.0-1.0 (newest last) */
  levels: number[];
  /** When false, waves animate at minimal idle amplitude */
  isActive: boolean;
  /** Container height in px (default: 120) */
  height?: number;
}

// Per-wave config — matches macOS WaveformView.swift WaveConfig exactly
interface WaveConfig {
  frequency: number;
  speed: number;         // radians per second
  amplitudeScale: number;
  smoothUp: number;      // attack rate (0-1)
  smoothDown: number;    // release rate
  phaseOffset: number;   // initial phase offset
  lineWidth: number;
  glowWidth: number;     // wider stroke behind for neon glow
  glowOpacity: number;
  color: [number, number, number]; // RGB 0-255
  isPrimary: boolean;
  historyOffset: number; // how many samples back this wave reads
}

// Matches macOS waveConfigs array — same frequencies, speeds, colors, offsets
const WAVE_CONFIGS: WaveConfig[] = [
  // Primary bold wave — brandPrimary #E50074
  { frequency: 1.5,  speed: 9.0,  amplitudeScale: 1.0,  smoothUp: 0.70, smoothDown: 0.20, phaseOffset: 0.0,  lineWidth: 3.0, glowWidth: 8.0,  glowOpacity: 0.20, color: [229, 0, 116],   isPrimary: true,  historyOffset: 0  },
  // Wave 2 — blue-purple (0.3, 0.4, 1.0)
  { frequency: 1.8,  speed: 7.2,  amplitudeScale: 0.82, smoothUp: 0.60, smoothDown: 0.18, phaseOffset: 1.2,  lineWidth: 1.5, glowWidth: 5.0,  glowOpacity: 0.18, color: [77, 102, 255],  isPrimary: false, historyOffset: 5  },
  // Wave 3 — purple (0.5, 0.2, 1.0)
  { frequency: 1.2,  speed: 11.5, amplitudeScale: 0.70, smoothUp: 0.55, smoothDown: 0.16, phaseOffset: 2.8,  lineWidth: 1.5, glowWidth: 5.0,  glowOpacity: 0.16, color: [128, 51, 255],  isPrimary: false, historyOffset: 10 },
  // Wave 4 — neonBlue #00C2FF
  { frequency: 2.1,  speed: 5.8,  amplitudeScale: 0.55, smoothUp: 0.50, smoothDown: 0.15, phaseOffset: 4.1,  lineWidth: 1.5, glowWidth: 5.0,  glowOpacity: 0.15, color: [0, 194, 255],   isPrimary: false, historyOffset: 15 },
  // Wave 5 — blue (0.2, 0.5, 1.0)
  { frequency: 0.9,  speed: 13.0, amplitudeScale: 0.40, smoothUp: 0.45, smoothDown: 0.15, phaseOffset: 5.5,  lineWidth: 1.5, glowWidth: 5.0,  glowOpacity: 0.15, color: [51, 128, 255],  isPrimary: false, historyOffset: 20 },
];

const IDLE_AMPLITUDE = 0.03;
const NUM_WAVES = WAVE_CONFIGS.length;

export function WaveformVisualizer({
  levels,
  isActive,
  height = 120,
}: WaveformVisualizerProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const animFrameRef = useRef<number>(0);
  const smoothedLevelsRef = useRef<number[]>(WAVE_CONFIGS.map(() => IDLE_AMPLITUDE));
  const jitterSeedsRef = useRef<number[]>(WAVE_CONFIGS.map(() => Math.random() * 1000));
  const levelsRef = useRef(levels);
  const isActiveRef = useRef(isActive);

  levelsRef.current = levels;
  isActiveRef.current = isActive;

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    function resize() {
      if (!canvas) return;
      const parent = canvas.parentElement;
      if (!parent) return;
      const dpr = window.devicePixelRatio || 1;
      // clientWidth on the parent includes padding; use the content box via computedStyle
      const style = getComputedStyle(parent);
      const w = parent.clientWidth - parseFloat(style.paddingLeft) - parseFloat(style.paddingRight);
      canvas.width = Math.round(w * dpr);
      canvas.height = Math.round(height * dpr);
      canvas.style.width = `${w}px`;
      canvas.style.height = `${height}px`;
      ctx!.setTransform(dpr, 0, 0, dpr, 0, 0);
    }
    resize();

    const observer = new ResizeObserver(resize);
    if (canvas.parentElement) observer.observe(canvas.parentElement);

    const draw = (time: number) => {
      const timeSec = time / 1000;
      const currentLevels = levelsRef.current;
      const active = isActiveRef.current;
      const smoothed = smoothedLevelsRef.current;
      const seeds = jitterSeedsRef.current;

      // Update smoothed levels per wave — matches macOS updateSmoothedLevels()
      for (let i = 0; i < NUM_WAVES; i++) {
        const cfg = WAVE_CONFIGS[i];

        let rawLevel: number;
        if (active && currentLevels.length > 0) {
          // Each wave reads from a different offset in the levels history
          const endIndex = Math.max(0, currentLevels.length - cfg.historyOffset);
          if (endIndex > 0) {
            const count = Math.min(endIndex, 3);
            const startIndex = endIndex - count;
            const slice = currentLevels.slice(startIndex, endIndex);
            const peak = Math.max(...slice);
            const avg = slice.reduce((a, b) => a + b, 0) / count;
            const base = Math.max(peak * 0.7 + avg * 0.3, IDLE_AMPLITUDE);
            // Compress dynamic range and boost visibility
            // pow(x, 0.45) expands low values more aggressively than 0.6
            // then scale up so even modest input fills the waveform area
            rawLevel = Math.pow(base, 0.45) * 1.4;
          } else {
            rawLevel = IDLE_AMPLITUDE;
          }
        } else {
          rawLevel = IDLE_AMPLITUDE;
        }

        // Per-wave jitter for natural variation
        const jitter = 0.85 + 0.30 * (0.5 + 0.5 * Math.sin(timeSec * 3.7 + seeds[i]));
        const target = rawLevel * cfg.amplitudeScale * jitter;

        // When active, ensure a minimum visible amplitude so waves are clearly "alive"
        const activeFloor = active ? 0.08 : 0;
        // Idle sine breathing so waves move independently in silence
        const idleBreathing = IDLE_AMPLITUDE * (0.5 + 0.5 * Math.sin(timeSec * (1.2 + i * 0.3) + seeds[i]));
        const finalTarget = Math.max(target, idleBreathing, activeFloor);

        const delta = finalTarget - smoothed[i];
        const rate = delta > 0 ? cfg.smoothUp : cfg.smoothDown;
        smoothed[i] += delta * rate;
      }

      // Draw — use canvas backing size divided by DPR for CSS pixel width
      const dpr = window.devicePixelRatio || 1;
      const w = canvas.width / dpr;
      const h = height;
      ctx.clearRect(0, 0, w, h);

      const midX = w / 2;
      const midY = h / 2;
      // Add padding to account for glow width and line width so waves don't get clipped
      const maxGlowWidth = Math.max(...WAVE_CONFIGS.map(c => c.glowWidth));
      const padding = 4 + maxGlowWidth / 2;
      const maxAmplitude = Math.min(midY, (w / 2)) - padding;

      // Draw waves back to front (wave 4 first, primary last on top)
      for (let i = NUM_WAVES - 1; i >= 0; i--) {
        const cfg = WAVE_CONFIGS[i];
        const wavePhase = -(timeSec * cfg.speed) + cfg.phaseOffset;
        const level = smoothed[i];

        // Build path — parabolic envelope -(x^2)+1 matches macOS exactly
        ctx.beginPath();
        for (let x = 0; x <= w; x++) {
          const normalized = (x - midX) / midX;
          const envelope = -(normalized * normalized) + 1.0;
          const y = envelope * maxAmplitude * level
            * Math.sin(2 * Math.PI * (x / w) * cfg.frequency + wavePhase)
            + midY;
          if (x === 0) ctx.moveTo(x, y);
          else ctx.lineTo(x, y);
        }

        const [r, g, b] = cfg.color;
        const opacity = cfg.isPrimary
          ? 1.0
          : Math.min(1.0, (i / NUM_WAVES) / 3.0 + 1.0 / 3.0);

        // Glow pass — wider translucent stroke behind main line
        ctx.save();
        if (!cfg.isPrimary) ctx.globalCompositeOperation = "screen";
        ctx.strokeStyle = `rgba(${r}, ${g}, ${b}, ${cfg.glowOpacity})`;
        ctx.lineWidth = cfg.glowWidth;
        ctx.lineCap = "round";
        ctx.lineJoin = "round";
        ctx.stroke();
        ctx.restore();

        // Main stroke
        ctx.save();
        if (!cfg.isPrimary) ctx.globalCompositeOperation = "screen";
        ctx.strokeStyle = `rgba(${r}, ${g}, ${b}, ${opacity})`;
        ctx.lineWidth = cfg.lineWidth;
        ctx.lineCap = "round";
        ctx.lineJoin = "round";
        ctx.stroke();
        ctx.restore();
      }

      animFrameRef.current = requestAnimationFrame(draw);
    };

    animFrameRef.current = requestAnimationFrame(draw);
    return () => {
      cancelAnimationFrame(animFrameRef.current);
      observer.disconnect();
    };
  }, [height]);

  return (
    <canvas
      ref={canvasRef}
      style={{ display: "block", width: "100%", height }}
    />
  );
}
