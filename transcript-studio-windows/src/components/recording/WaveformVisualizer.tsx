import { useEffect, useRef } from "react";

interface WaveformVisualizerProps {
  /** Ref to audio level values in range 0.0-1.0 (newest last) */
  levelsRef: React.RefObject<number[]>;
  /** When false, waves animate at minimal idle amplitude */
  isActive: boolean;
  /** Container height in px (default: 120) */
  height?: number;
}

// ── Color gradient (blue → violet → magenta → cyan) ────────────────
const GRADIENT_STOPS: [number, number, number, number][] = [
  [0.00,  20,  60, 180],
  [0.15,  40, 100, 240],
  [0.30,  80,  60, 255],
  [0.45, 130,  30, 240],
  [0.55, 160,  20, 200],
  [0.70, 190,  30, 180],
  [0.85, 140,  60, 220],
  [0.95,  40, 160, 255],
  [1.00,  20, 120, 220],
];

const IDLE_AMPLITUDE = 0.01;

// ── Wave configurations ─────────────────────────────────────────────
// Each wave is a COMPOUND of two sine components for organic shapes.
// Waves have genuinely different frequencies + speeds → they cross
// and weave through each other naturally.
interface WaveConfig {
  freq1: number;   speed1: number;   amp1: number;
  freq2: number;   speed2: number;   amp2: number;
  phase: number;
  ampScale: number;
  lineWidth: number;
  glowRadius: number;
  historyOffset: number;
  smoothUp: number;
  smoothDown: number;
}

const NUM_WAVES = 16;

const WAVES: WaveConfig[] = [
  // ── Core waves (brightest, thickest) ──
  { freq1: 2.0,  speed1: 10.0, amp1: 0.70,  freq2: 3.2,  speed2: 6.5,  amp2: 0.30,  phase: 0.0,  ampScale: 1.00, lineWidth: 1.6, glowRadius: 12, historyOffset: 0,  smoothUp: 0.22, smoothDown: 0.04 },
  { freq1: 2.2,  speed1: 9.0,  amp1: 0.65,  freq2: 3.5,  speed2: 7.0,  amp2: 0.35,  phase: 0.8,  ampScale: 0.95, lineWidth: 1.4, glowRadius: 10, historyOffset: 2,  smoothUp: 0.20, smoothDown: 0.04 },
  { freq1: 1.8,  speed1: 11.0, amp1: 0.72,  freq2: 2.8,  speed2: 5.5,  amp2: 0.28,  phase: 1.5,  ampScale: 0.92, lineWidth: 1.3, glowRadius: 10, historyOffset: 3,  smoothUp: 0.20, smoothDown: 0.05 },
  { freq1: 2.4,  speed1: 8.5,  amp1: 0.60,  freq2: 3.8,  speed2: 7.5,  amp2: 0.40,  phase: 2.3,  ampScale: 0.88, lineWidth: 1.2, glowRadius: 9,  historyOffset: 4,  smoothUp: 0.19, smoothDown: 0.05 },
  // ── Mid waves ──
  { freq1: 2.6,  speed1: 7.5,  amp1: 0.68,  freq2: 1.9,  speed2: 12.0, amp2: 0.32,  phase: 3.0,  ampScale: 0.82, lineWidth: 1.0, glowRadius: 8,  historyOffset: 6,  smoothUp: 0.18, smoothDown: 0.05 },
  { freq1: 1.9,  speed1: 12.5, amp1: 0.55,  freq2: 3.0,  speed2: 8.0,  amp2: 0.45,  phase: 3.7,  ampScale: 0.78, lineWidth: 1.0, glowRadius: 8,  historyOffset: 7,  smoothUp: 0.18, smoothDown: 0.05 },
  { freq1: 2.8,  speed1: 7.0,  amp1: 0.62,  freq2: 2.1,  speed2: 11.0, amp2: 0.38,  phase: 4.4,  ampScale: 0.74, lineWidth: 0.9, glowRadius: 7,  historyOffset: 8,  smoothUp: 0.17, smoothDown: 0.06 },
  { freq1: 2.1,  speed1: 10.5, amp1: 0.58,  freq2: 3.4,  speed2: 6.0,  amp2: 0.42,  phase: 5.1,  ampScale: 0.70, lineWidth: 0.9, glowRadius: 7,  historyOffset: 10, smoothUp: 0.17, smoothDown: 0.06 },
  // ── Outer waves (thinner, dimmer) ──
  { freq1: 3.0,  speed1: 6.5,  amp1: 0.66,  freq2: 2.3,  speed2: 13.0, amp2: 0.34,  phase: 5.8,  ampScale: 0.62, lineWidth: 0.7, glowRadius: 6,  historyOffset: 12, smoothUp: 0.16, smoothDown: 0.06 },
  { freq1: 1.8,  speed1: 13.5, amp1: 0.52,  freq2: 2.6,  speed2: 9.0,  amp2: 0.48,  phase: 6.5,  ampScale: 0.58, lineWidth: 0.7, glowRadius: 6,  historyOffset: 13, smoothUp: 0.16, smoothDown: 0.06 },
  { freq1: 3.2,  speed1: 6.0,  amp1: 0.64,  freq2: 1.8,  speed2: 14.0, amp2: 0.36,  phase: 7.2,  ampScale: 0.52, lineWidth: 0.6, glowRadius: 5,  historyOffset: 14, smoothUp: 0.15, smoothDown: 0.07 },
  { freq1: 2.3,  speed1: 11.5, amp1: 0.50,  freq2: 3.6,  speed2: 5.5,  amp2: 0.50,  phase: 7.9,  ampScale: 0.48, lineWidth: 0.6, glowRadius: 5,  historyOffset: 16, smoothUp: 0.15, smoothDown: 0.07 },
  // ── Background wisps ──
  { freq1: 2.5,  speed1: 8.0,  amp1: 0.56,  freq2: 3.1,  speed2: 10.0, amp2: 0.44,  phase: 8.6,  ampScale: 0.42, lineWidth: 0.5, glowRadius: 4,  historyOffset: 18, smoothUp: 0.14, smoothDown: 0.07 },
  { freq1: 1.9,  speed1: 14.0, amp1: 0.48,  freq2: 2.7,  speed2: 7.5,  amp2: 0.52,  phase: 9.3,  ampScale: 0.38, lineWidth: 0.5, glowRadius: 4,  historyOffset: 19, smoothUp: 0.14, smoothDown: 0.07 },
  { freq1: 3.1,  speed1: 5.5,  amp1: 0.60,  freq2: 2.0,  speed2: 12.5, amp2: 0.40,  phase: 10.0, ampScale: 0.34, lineWidth: 0.4, glowRadius: 3,  historyOffset: 21, smoothUp: 0.13, smoothDown: 0.08 },
  { freq1: 2.7,  speed1: 9.5,  amp1: 0.54,  freq2: 3.3,  speed2: 6.5,  amp2: 0.46,  phase: 10.7, ampScale: 0.30, lineWidth: 0.4, glowRadius: 3,  historyOffset: 23, smoothUp: 0.13, smoothDown: 0.08 },
];

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
  const smoothedRef = useRef(new Float32Array(NUM_WAVES).fill(IDLE_AMPLITUDE));
  const isActiveRef = useRef(isActive);

  isActiveRef.current = isActive;

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    let gradCache: { w: number; map: Map<number, CanvasGradient> } = { w: 0, map: new Map() };

    function getGradient(w: number, opacity: number): CanvasGradient {
      const key = Math.round(opacity * 100);
      if (gradCache.w !== w) gradCache = { w, map: new Map() };
      let g = gradCache.map.get(key);
      if (!g) {
        g = buildGradient(ctx!, w, opacity);
        gradCache.map.set(key, g);
      }
      return g;
    }

    function resize() {
      if (!canvas) return;
      const parent = canvas.parentElement;
      if (!parent) return;
      const dpr = window.devicePixelRatio || 1;
      const ps = getComputedStyle(parent);
      const w = parent.clientWidth - parseFloat(ps.paddingLeft) - parseFloat(ps.paddingRight);
      canvas.width = Math.round(w * dpr);
      canvas.height = Math.round(height * dpr);
      canvas.style.width = `${w}px`;
      canvas.style.height = `${height}px`;
      ctx!.setTransform(dpr, 0, 0, dpr, 0, 0);
      gradCache = { w: 0, map: new Map() };
    }
    resize();

    const observer = new ResizeObserver(resize);
    if (canvas.parentElement) observer.observe(canvas.parentElement);

    const draw = (time: number) => {
      const t = time / 1000;
      const levels = levelsRef.current;
      const active = isActiveRef.current;
      const smoothed = smoothedRef.current;

      // ── Update per-wave audio levels ──
      for (let i = 0; i < NUM_WAVES; i++) {
        const cfg = WAVES[i];
        let target = IDLE_AMPLITUDE;

        if (active && levels.length > 0) {
          const end = Math.max(0, levels.length - cfg.historyOffset);
          if (end > 0) {
            const count = Math.min(end, 4);
            const start = end - count;
            let sum = 0;
            for (let j = start; j < end; j++) sum += levels[j];
            const peak = Math.max(...levels.slice(start, end));
            const avg = sum / count;
            target = Math.max(peak * 0.6 + avg * 0.4, IDLE_AMPLITUDE);
          }
        }

        target = Math.pow(target, 0.6); // expand low-end visibility

        const delta = target - smoothed[i];
        smoothed[i] += delta * (delta > 0 ? cfg.smoothUp : cfg.smoothDown);
      }

      // ── Canvas ──
      const dpr = window.devicePixelRatio || 1;
      const w = canvas.width / dpr;
      const h = height;
      ctx.clearRect(0, 0, w, h);

      const midX = w / 2;
      const midY = h / 2;
      const maxAmp = midY - 4;

      // Draw back to front (last wave = background, first = foreground)
      for (let i = NUM_WAVES - 1; i >= 0; i--) {
        const cfg = WAVES[i];
        const level = smoothed[i] * cfg.ampScale;

        // Each wave = compound of two sine components
        const phase1 = -(t * cfg.speed1) + cfg.phase;
        const phase2 = -(t * cfg.speed2) + cfg.phase * 1.3;

        // Compute all wave points first
        const step = 3;
        const numPts = Math.floor(w / step) + 1;
        const pts: { x: number; y: number }[] = new Array(numPts);
        for (let k = 0; k < numPts; k++) {
          const x = k * step;
          const nx = (x - midX) / midX;  // -1 to 1
          const n2 = nx * nx;
          const envelope = -(n2 * n2) + 1.0;  // quartic: wider than parabolic
          const xn = x / w;  // 0 to 1

          // Compound wave: two sines with different freq/speed
          const wave = cfg.amp1 * Math.sin(2 * Math.PI * cfg.freq1 * xn + phase1)
                     + cfg.amp2 * Math.sin(2 * Math.PI * cfg.freq2 * xn + phase2);

          pts[k] = { x, y: envelope * maxAmp * level * wave + midY };
        }

        // Draw smooth curve using quadratic bezier through midpoints
        ctx.beginPath();
        ctx.moveTo(pts[0].x, pts[0].y);
        for (let k = 0; k < numPts - 1; k++) {
          const mx = (pts[k].x + pts[k + 1].x) / 2;
          const my = (pts[k].y + pts[k + 1].y) / 2;
          ctx.quadraticCurveTo(pts[k].x, pts[k].y, mx, my);
        }
        // Final segment to last point
        const last = pts[numPts - 1];
        ctx.lineTo(last.x, last.y);

        // Opacity based on ampScale (core = bright, background = dim)
        const opacity = 0.25 + 0.75 * cfg.ampScale;

        // Glow pass
        ctx.save();
        ctx.globalCompositeOperation = "lighter";
        ctx.shadowBlur = cfg.glowRadius;
        ctx.shadowColor = `rgba(100, 60, 240, ${opacity * 0.5})`;
        ctx.strokeStyle = getGradient(w, opacity);
        ctx.lineWidth = cfg.lineWidth;
        ctx.lineCap = "round";
        ctx.lineJoin = "round";
        ctx.stroke();
        ctx.restore();

        // Crisp core pass
        ctx.save();
        ctx.globalCompositeOperation = "lighter";
        ctx.strokeStyle = getGradient(w, opacity * 0.6);
        ctx.lineWidth = cfg.lineWidth * 0.5;
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
