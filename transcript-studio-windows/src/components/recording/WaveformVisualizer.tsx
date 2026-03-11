import { useEffect, useRef } from "react";

interface WaveformVisualizerProps {
  /** Ref to audio level values in range 0.0-1.0 (newest last) */
  levelsRef: React.RefObject<number[]>;
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
  glowRadius: number;    // shadowBlur radius for neon glow
  historyOffset: number; // how many samples back this wave reads
}

// Gradient color stops for the X-axis color sweep (blue → violet → magenta → cyan)
// Each stop: [position 0-1, r, g, b]
const GRADIENT_STOPS: [number, number, number, number][] = [
  [0.00,  20,  60, 180],   // deep blue (far left)
  [0.15,  40, 100, 240],   // blue
  [0.30,  80,  60, 255],   // blue-violet
  [0.45, 130,  30, 240],   // violet
  [0.55, 160,  20, 200],   // purple-magenta
  [0.70, 190,  30, 180],   // magenta
  [0.85, 140,  60, 220],   // magenta-violet
  [0.95,  40, 160, 255],   // cyan highlight
  [1.00,  20, 120, 220],   // teal (far right)
];

// 18 waves — thin threads that weave together into a neon fabric
const WAVE_CONFIGS: WaveConfig[] = [
  // Primary — brightest, slightly thicker
  { frequency: 1.5,  speed: 8.5,  amplitudeScale: 1.0,  smoothUp: 0.70, smoothDown: 0.20, phaseOffset: 0.0,  lineWidth: 1.5, glowRadius: 12, historyOffset: 0  },
  // Blue core threads
  { frequency: 1.8,  speed: 7.0,  amplitudeScale: 0.92, smoothUp: 0.65, smoothDown: 0.18, phaseOffset: 0.7,  lineWidth: 1.0, glowRadius: 8,  historyOffset: 2  },
  { frequency: 1.2,  speed: 10.5, amplitudeScale: 0.88, smoothUp: 0.62, smoothDown: 0.17, phaseOffset: 1.5,  lineWidth: 0.8, glowRadius: 6,  historyOffset: 3  },
  { frequency: 2.0,  speed: 6.8,  amplitudeScale: 0.85, smoothUp: 0.60, smoothDown: 0.17, phaseOffset: 2.1,  lineWidth: 0.8, glowRadius: 6,  historyOffset: 4  },
  // Blue-violet transition
  { frequency: 2.4,  speed: 5.8,  amplitudeScale: 0.80, smoothUp: 0.58, smoothDown: 0.16, phaseOffset: 2.8,  lineWidth: 0.8, glowRadius: 6,  historyOffset: 5  },
  { frequency: 0.9,  speed: 12.0, amplitudeScale: 0.78, smoothUp: 0.56, smoothDown: 0.16, phaseOffset: 3.3,  lineWidth: 1.0, glowRadius: 8,  historyOffset: 7  },
  { frequency: 1.6,  speed: 9.2,  amplitudeScale: 0.74, smoothUp: 0.54, smoothDown: 0.15, phaseOffset: 3.9,  lineWidth: 0.6, glowRadius: 5,  historyOffset: 8  },
  // Violet core
  { frequency: 2.8,  speed: 4.5,  amplitudeScale: 0.70, smoothUp: 0.52, smoothDown: 0.15, phaseOffset: 4.5,  lineWidth: 0.8, glowRadius: 6,  historyOffset: 9  },
  { frequency: 1.1,  speed: 13.0, amplitudeScale: 0.66, smoothUp: 0.50, smoothDown: 0.14, phaseOffset: 5.1,  lineWidth: 0.6, glowRadius: 5,  historyOffset: 10 },
  { frequency: 1.9,  speed: 7.5,  amplitudeScale: 0.62, smoothUp: 0.48, smoothDown: 0.14, phaseOffset: 5.7,  lineWidth: 0.8, glowRadius: 6,  historyOffset: 11 },
  // Purple-magenta accents
  { frequency: 3.0,  speed: 3.8,  amplitudeScale: 0.58, smoothUp: 0.46, smoothDown: 0.14, phaseOffset: 6.2,  lineWidth: 0.6, glowRadius: 5,  historyOffset: 12 },
  { frequency: 0.7,  speed: 14.5, amplitudeScale: 0.54, smoothUp: 0.44, smoothDown: 0.13, phaseOffset: 6.8,  lineWidth: 0.6, glowRadius: 5,  historyOffset: 14 },
  { frequency: 2.2,  speed: 6.0,  amplitudeScale: 0.50, smoothUp: 0.42, smoothDown: 0.13, phaseOffset: 7.4,  lineWidth: 0.6, glowRadius: 4,  historyOffset: 15 },
  // Cyan/electric highlights
  { frequency: 1.4,  speed: 11.0, amplitudeScale: 0.46, smoothUp: 0.40, smoothDown: 0.13, phaseOffset: 8.0,  lineWidth: 0.6, glowRadius: 8,  historyOffset: 16 },
  { frequency: 3.5,  speed: 3.2,  amplitudeScale: 0.42, smoothUp: 0.38, smoothDown: 0.12, phaseOffset: 8.6,  lineWidth: 0.5, glowRadius: 4,  historyOffset: 17 },
  // Deep background threads
  { frequency: 0.6,  speed: 15.5, amplitudeScale: 0.38, smoothUp: 0.36, smoothDown: 0.12, phaseOffset: 9.2,  lineWidth: 0.5, glowRadius: 4,  historyOffset: 18 },
  { frequency: 2.6,  speed: 5.0,  amplitudeScale: 0.34, smoothUp: 0.34, smoothDown: 0.11, phaseOffset: 9.8,  lineWidth: 0.4, glowRadius: 3,  historyOffset: 20 },
  { frequency: 1.7,  speed: 8.0,  amplitudeScale: 0.30, smoothUp: 0.32, smoothDown: 0.11, phaseOffset: 10.4, lineWidth: 0.4, glowRadius: 3,  historyOffset: 22 },
];

const IDLE_AMPLITUDE = 0.03;
const NUM_WAVES = WAVE_CONFIGS.length;

// Pre-build a reusable gradient for a given canvas width
function buildGradient(ctx: CanvasRenderingContext2D, w: number, opacity: number): CanvasGradient {
  const grad = ctx.createLinearGradient(0, 0, w, 0);
  for (const [pos, r, g, b] of GRADIENT_STOPS) {
    grad.addColorStop(pos, `rgba(${r}, ${g}, ${b}, ${opacity})`);
  }
  return grad;
}

export function WaveformVisualizer({
  levelsRef,
  isActive,
  height = 120,
}: WaveformVisualizerProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const animFrameRef = useRef<number>(0);
  const smoothedLevelsRef = useRef<number[]>(WAVE_CONFIGS.map(() => IDLE_AMPLITUDE));
  const jitterSeedsRef = useRef<number[]>(WAVE_CONFIGS.map(() => Math.random() * 1000));
  const isActiveRef = useRef(isActive);

  isActiveRef.current = isActive;

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    // Cache gradients — rebuilt on resize
    let gradientCache: { w: number; grads: Map<number, CanvasGradient> } = { w: 0, grads: new Map() };

    function getGradient(w: number, opacity: number): CanvasGradient {
      // Round opacity to 2 decimals as cache key
      const key = Math.round(opacity * 100);
      if (gradientCache.w !== w) {
        gradientCache = { w, grads: new Map() };
      }
      let g = gradientCache.grads.get(key);
      if (!g) {
        g = buildGradient(ctx!, w, opacity);
        gradientCache.grads.set(key, g);
      }
      return g;
    }

    function resize() {
      if (!canvas) return;
      const parent = canvas.parentElement;
      if (!parent) return;
      const dpr = window.devicePixelRatio || 1;
      const style = getComputedStyle(parent);
      const w = parent.clientWidth - parseFloat(style.paddingLeft) - parseFloat(style.paddingRight);
      canvas.width = Math.round(w * dpr);
      canvas.height = Math.round(height * dpr);
      canvas.style.width = `${w}px`;
      canvas.style.height = `${height}px`;
      ctx!.setTransform(dpr, 0, 0, dpr, 0, 0);
      // Invalidate gradient cache on resize
      gradientCache = { w: 0, grads: new Map() };
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

      // Update smoothed levels per wave
      for (let i = 0; i < NUM_WAVES; i++) {
        const cfg = WAVE_CONFIGS[i];

        let rawLevel: number;
        if (active && currentLevels.length > 0) {
          const endIndex = Math.max(0, currentLevels.length - cfg.historyOffset);
          if (endIndex > 0) {
            const count = Math.min(endIndex, 3);
            const startIndex = endIndex - count;
            const slice = currentLevels.slice(startIndex, endIndex);
            const peak = Math.max(...slice);
            const avg = slice.reduce((a, b) => a + b, 0) / count;
            const base = Math.max(peak * 0.7 + avg * 0.3, IDLE_AMPLITUDE);
            rawLevel = Math.pow(base, 0.45) * 1.4;
          } else {
            rawLevel = IDLE_AMPLITUDE;
          }
        } else {
          rawLevel = IDLE_AMPLITUDE;
        }

        const jitter = 0.85 + 0.30 * (0.5 + 0.5 * Math.sin(timeSec * 3.7 + seeds[i]));
        const target = rawLevel * cfg.amplitudeScale * jitter;

        const activeFloor = active ? 0.08 : 0;
        const idleBreathing = IDLE_AMPLITUDE * (0.5 + 0.5 * Math.sin(timeSec * (1.2 + i * 0.3) + seeds[i]));
        const finalTarget = Math.max(target, idleBreathing, activeFloor);

        const delta = finalTarget - smoothed[i];
        const rate = delta > 0 ? cfg.smoothUp : cfg.smoothDown;
        smoothed[i] += delta * rate;
      }

      const dpr = window.devicePixelRatio || 1;
      const w = canvas.width / dpr;
      const h = height;
      ctx.clearRect(0, 0, w, h);

      const midX = w / 2;
      const midY = h / 2;
      const padding = 16;
      const maxAmplitude = Math.min(midY, (w / 2)) - padding;

      // Draw waves back to front
      for (let i = NUM_WAVES - 1; i >= 0; i--) {
        const cfg = WAVE_CONFIGS[i];
        const wavePhase = -(timeSec * cfg.speed) + cfg.phaseOffset;
        const level = Math.min(smoothed[i], 1.0);

        // Build path — flatter envelope -(x^4)+1 for wider reach toward edges
        ctx.beginPath();
        for (let x = 0; x <= w; x++) {
          const normalized = (x - midX) / midX;
          const n2 = normalized * normalized;
          const envelope = -(n2 * n2) + 1.0; // quartic: flatter center, wider reach
          const y = envelope * maxAmplitude * level
            * Math.sin(2 * Math.PI * (x / w) * cfg.frequency + wavePhase)
            + midY;
          if (x === 0) ctx.moveTo(x, y);
          else ctx.lineTo(x, y);
        }

        const isPrimary = i === 0;
        const opacity = isPrimary
          ? 0.9
          : Math.min(0.8, 0.25 + (1.0 - i / NUM_WAVES) * 0.55);

        // Neon glow via shadowBlur — the key to the soft bloom effect
        ctx.save();
        ctx.globalCompositeOperation = "lighter";
        ctx.shadowBlur = cfg.glowRadius;
        // Shadow color follows the gradient midpoint for a cohesive glow
        ctx.shadowColor = `rgba(100, 60, 240, ${opacity * 0.6})`;
        ctx.strokeStyle = getGradient(w, opacity);
        ctx.lineWidth = cfg.lineWidth;
        ctx.lineCap = "round";
        ctx.lineJoin = "round";
        ctx.stroke();
        ctx.restore();

        // Second crisp pass without shadow — bright core line
        ctx.save();
        ctx.globalCompositeOperation = "lighter";
        ctx.strokeStyle = getGradient(w, opacity * 0.7);
        ctx.lineWidth = cfg.lineWidth * 0.6;
        ctx.lineCap = "round";
        ctx.lineJoin = "round";
        ctx.stroke();
        ctx.restore();
      }

      ctx.globalCompositeOperation = "source-over";
      animFrameRef.current = requestAnimationFrame(draw);
    };

    animFrameRef.current = requestAnimationFrame(draw);
    return () => {
      cancelAnimationFrame(animFrameRef.current);
      animFrameRef.current = 0;
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
