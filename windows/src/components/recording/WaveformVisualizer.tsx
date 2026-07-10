import { useEffect, useRef } from "react";

interface WaveformVisualizerProps {
  /** Ref to processed envelope levels in range 0.0-1.0 (newest last, max 40) */
  levelsRef: React.RefObject<number[]>;
  /** When false, the waveform collapses to a calm baseline */
  isActive: boolean;
  /** Container height in px (default: 120) */
  height?: number;
}

const HISTORY_LENGTH = 40;

// ── Color gradient (blue → violet → magenta → cyan) ────────────────
const GRADIENT_STOPS = [
  { pos: 0.0, color: "rgb(20, 61, 179)" },
  { pos: 0.3, color: "rgb(79, 61, 255)" },
  { pos: 0.55, color: "rgb(161, 20, 199)" },
  { pos: 0.95, color: "rgb(41, 161, 255)" },
];

/**
 * Scrolling history waveform: renders the last 40 processed envelope levels
 * as a smooth mirrored shape around the vertical center. The incoming values
 * are final (RMS → dBFS → envelope in Rust) — no smoothing, no artificial
 * motion; silence renders as a thin calm baseline.
 */
export function WaveformVisualizer({
  levelsRef,
  isActive,
  height = 120,
}: WaveformVisualizerProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const animFrameRef = useRef<number>(0);
  const isActiveRef = useRef(isActive);

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

    const draw = () => {
      const dpr = window.devicePixelRatio || 1;
      const w = canvas.width / dpr;
      const h = height;
      ctx.clearRect(0, 0, w, h);

      const midY = h / 2;
      const maxAmp = midY - Math.min(Math.max(3, midY * 0.12), 12);

      // Pad to a fixed length so the wave scrolls left as history fills.
      const raw = levelsRef.current ?? [];
      const active = isActiveRef.current;
      const levels: number[] = new Array(HISTORY_LENGTH).fill(0);
      const src = raw.slice(-HISTORY_LENGTH);
      for (let i = 0; i < src.length; i++) {
        levels[HISTORY_LENGTH - src.length + i] = active ? src[i] : 0;
      }

      if (maxAmp > 1 && w > 0) {
        const stepX = w / (HISTORY_LENGTH - 1);
        // Baseline of 1px so silence reads as a thin calm line.
        const amps = levels.map((v) => Math.max(1, Math.min(1, Math.max(0, v)) * maxAmp));

        const gradient = ctx.createLinearGradient(0, 0, w, 0);
        for (const stop of GRADIENT_STOPS) gradient.addColorStop(stop.pos, stop.color);

        ctx.beginPath();
        smoothLine(ctx, amps.map((a, i) => [i * stepX, midY - a] as [number, number]), true);
        smoothLine(
          ctx,
          amps.map((a, i) => [i * stepX, midY + a] as [number, number]).reverse(),
          false
        );
        ctx.closePath();

        ctx.fillStyle = gradient;
        ctx.globalAlpha = 0.35;
        ctx.fill();

        ctx.globalAlpha = 1;
        ctx.strokeStyle = gradient;
        ctx.lineWidth = 1.5;
        ctx.lineCap = "round";
        ctx.lineJoin = "round";
        ctx.stroke();
      }

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
    <canvas ref={canvasRef} style={{ display: "block", width: "100%", height }} />
  );
}

/** Adds a smooth polyline (quad curves via midpoints) to the current path. */
function smoothLine(
  ctx: CanvasRenderingContext2D,
  points: [number, number][],
  moveToFirst: boolean
) {
  if (points.length === 0) return;
  if (moveToFirst) ctx.moveTo(points[0][0], points[0][1]);
  else ctx.lineTo(points[0][0], points[0][1]);
  for (let i = 1; i < points.length - 1; i++) {
    const midX = (points[i][0] + points[i + 1][0]) / 2;
    const midY = (points[i][1] + points[i + 1][1]) / 2;
    ctx.quadraticCurveTo(points[i][0], points[i][1], midX, midY);
  }
  const last = points[points.length - 1];
  ctx.lineTo(last[0], last[1]);
}
