import { useEffect, useRef } from "react";
import { HISTORY_SIZE } from "../../hooks/useAudioLevel";

interface WaveformVisualizerProps {
  /** Ref to processed envelope levels in range 0.0-1.0 (newest last, max HISTORY_SIZE) */
  levelsRef: React.RefObject<number[]>;
  /** When false, the waveform collapses to a calm baseline */
  isActive: boolean;
  /** Container height in px (default: 120) */
  height?: number;
  /** Number of strands to draw (default: 7 above 64px, 4 below) */
  strands?: number;
}

// ── SiriWave math — kept identical to WaveformShader.metal ─────────
//
//   y(x) = A(x) * carrier(x, t) * g(x)
//   g(x) = (K/(K + x^K))^K, K = 4, x in [-2, 2]
//
// The attenuation envelope keeps the wave full in the middle and tapers it to a
// point at both edges. A(x) is the scrolled envelope history on the left,
// cross-fading into the LIVE level on the right (weight t*t*0.85) so fresh
// speech is visible immediately instead of being squashed by the attenuation.
const ATT_K = 4;
const attenuation = (x: number) => Math.pow(ATT_K / (ATT_K + Math.pow(x, ATT_K)), ATT_K);

/** Steps per strand polyline. */
const STEPS = 160;

interface Strand {
  amp: number;
  k: number;
  speed: number;
  phase: number;
  w: number;
  alpha: number;
  color: string;
}

// Mirror pairs (same k, phase offset pi) give the braided iOS look. Palette runs
// outermost -> innermost: blue -> cyan -> purple -> pink, identical to the Metal
// shader so macOS and Windows look the same.
const STRANDS: Strand[] = [
  { amp: 1.0, k: 6.0, speed: 1.1, phase: 0.0, w: 2.4, alpha: 0.95, color: "51, 102, 255" },
  { amp: 0.9, k: 6.0, speed: 1.1, phase: 3.14, w: 2.4, alpha: 0.95, color: "51, 102, 255" },
  { amp: 0.75, k: 8.5, speed: 1.45, phase: 1.2, w: 1.9, alpha: 0.85, color: "0, 204, 255" },
  { amp: 0.62, k: 8.5, speed: 1.45, phase: 4.34, w: 1.9, alpha: 0.85, color: "0, 204, 255" },
  { amp: 0.5, k: 11.0, speed: 1.8, phase: 2.2, w: 1.5, alpha: 0.75, color: "153, 51, 230" },
  { amp: 0.42, k: 11.0, speed: 1.8, phase: 5.34, w: 1.5, alpha: 0.75, color: "153, 51, 230" },
  { amp: 0.3, k: 14.0, speed: 2.2, phase: 0.7, w: 1.2, alpha: 0.65, color: "255, 77, 153" },
];

const CORE: Strand = {
  amp: 0.14,
  k: 4,
  speed: 0.8,
  phase: 1.6,
  w: 1.4,
  alpha: 1,
  color: "179, 102, 255",
};

/**
 * SiriWave-style neon waveform: seven braided strands plus a bright core line,
 * scrolling the last 3 seconds of processed envelope levels from right (new) to
 * left (old). Values arrive final from the Rust envelope (RMS -> dBFS ->
 * noise-floor tracking -> attack/release) — no smoothing and no artificial
 * motion here, so silence renders as a flat line in the middle.
 */
export function WaveformVisualizer({
  levelsRef,
  isActive,
  height = 120,
  strands,
}: WaveformVisualizerProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const animFrameRef = useRef<number>(0);
  const isActiveRef = useRef(isActive);
  // Must stay even below the threshold: STRANDS is ordered in mirror pairs and
  // an odd count leaves one carrier without its phase-offset twin.
  const strandCount = strands ?? (height >= 64 ? 7 : 4);

  isActiveRef.current = isActive;

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext("2d", { alpha: true });
    if (!ctx) return;

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
    }
    resize();

    const observer = new ResizeObserver(resize);
    if (canvas.parentElement) observer.observe(canvas.parentElement);

    // Phase clock lives in the RAF loop: phaseTime += dt * (2.2 + live * 5.5),
    // so the wave is calm when silent and energetic during loud speech.
    let phaseTime = 0;
    let lastFrame = performance.now();

    const draw = (now: number) => {
      const dpr = window.devicePixelRatio || 1;
      const w = canvas.width / dpr;
      const h = height;
      const cy = h / 2;
      const maxH = h * 0.46;

      const active = isActiveRef.current;
      const raw = active ? levelsRef.current ?? [] : [];
      // Pad to a fixed length so the wave scrolls in from the right while the
      // history is still filling.
      const levels: number[] = new Array(HISTORY_SIZE).fill(0);
      const src = raw.slice(-HISTORY_SIZE);
      for (let i = 0; i < src.length; i++) {
        levels[HISTORY_SIZE - src.length + i] = Math.max(0, Math.min(1, src[i]));
      }
      const live = levels[HISTORY_SIZE - 1];

      // Cosine interpolation between history points, so ~90 points across
      // ~900px do not show as steps.
      const envAt = (t: number) => {
        const f = Math.max(0, Math.min(1, t)) * (HISTORY_SIZE - 1);
        const i0 = f | 0;
        const i1 = Math.min(HISTORY_SIZE - 1, i0 + 1);
        const u = (1 - Math.cos((f - i0) * Math.PI)) / 2;
        return levels[i0] + (levels[i1] - levels[i0]) * u;
      };

      const dt = Math.min(64, now - lastFrame);
      lastFrame = now;
      phaseTime += (dt / 1000) * (2.2 + live * 5.5);

      ctx.clearRect(0, 0, w, h);

      if (w > 0 && maxH > 1) {
        ctx.globalCompositeOperation = "lighter";
        ctx.lineCap = "round";
        ctx.lineJoin = "round";

        // Reference values (shadowBlur 6 + live*24, widths 2.4..1.2) assume a
        // 120px canvas. Express the glow relative to maxH and scale the stroke
        // widths down on small surfaces, so the 32px pill stays crisp lines
        // instead of blobs.
        const glow = maxH * (0.11 + live * 0.44);
        const widthScale = Math.min(1, Math.max(0.4, h / 120));

        const strand = (s: Strand) => {
          ctx.beginPath();
          for (let i = 0; i <= STEPS; i++) {
            const t = i / STEPS;
            const gx = t * 4 - 2;
            const att = attenuation(gx);
            const liveW = t * t * 0.85;
            const A = envAt(t) * (1 - liveW) + live * liveW;
            const ph = phaseTime * s.speed + s.phase;
            const carrier =
              Math.sin(s.k * gx + ph) * 0.82 + Math.sin(s.k * 1.9 * gx + ph * 1.3 + 1.1) * 0.18;
            const y = cy + carrier * A * s.amp * maxH * att;
            if (i === 0) ctx.moveTo(t * w, y);
            else ctx.lineTo(t * w, y);
          }
          ctx.stroke();
        };

        for (let i = 0; i < Math.min(strandCount, STRANDS.length); i++) {
          const s = STRANDS[i];
          ctx.strokeStyle = `rgba(${s.color}, ${s.alpha})`;
          ctx.shadowColor = `rgb(${s.color})`;
          ctx.shadowBlur = glow;
          ctx.lineWidth = Math.max(0.7, s.w * widthScale);
          strand(s);
        }

        // Bright core line on top: flat in silence, lights up with speech.
        ctx.shadowBlur = glow * 0.6;
        ctx.shadowColor = `rgb(${CORE.color})`;
        ctx.strokeStyle = `rgba(${CORE.color}, ${0.5 + live * 0.45})`;
        ctx.lineWidth = Math.max(0.7, CORE.w * widthScale);
        strand(CORE);

        ctx.globalCompositeOperation = "source-over";
        ctx.shadowBlur = 0;
      }

      animFrameRef.current = requestAnimationFrame(draw);
    };

    animFrameRef.current = requestAnimationFrame(draw);

    return () => {
      cancelAnimationFrame(animFrameRef.current);
      animFrameRef.current = 0;
      observer.disconnect();
    };
  }, [height, strandCount]);

  return (
    <canvas ref={canvasRef} style={{ display: "block", width: "100%", height }} />
  );
}
