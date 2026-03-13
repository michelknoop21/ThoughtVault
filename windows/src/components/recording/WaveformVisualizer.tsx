import { useEffect, useRef } from "react";

interface WaveformVisualizerProps {
  /** Ref to audio level values in range 0.0-1.0 (newest last) */
  levelsRef: React.RefObject<number[]>;
  /** When false, waves animate at minimal idle amplitude */
  isActive: boolean;
  /** Container height in px (default: 120) */
  height?: number;
}

// ── Optimized Wave Configurations (8 waves) ─────────────────────────
interface WaveConfig {
  frequency: number;
  speed: number;
  amplitudeScale: number;
  phaseOffset: number;
  lineWidth: number;
  glowWidth: number;
  glowOpacity: number;
  historyOffset: number;
}

const WAVES: WaveConfig[] = [
  { frequency: 1.5, speed: 6.0, amplitudeScale: 1.0,  phaseOffset: 0.0, lineWidth: 2.0, glowWidth: 8.0, glowOpacity: 0.4,  historyOffset: 0 },
  { frequency: 1.8, speed: 5.2, amplitudeScale: 0.85, phaseOffset: 0.7, lineWidth: 1.5, glowWidth: 6.0, glowOpacity: 0.3,  historyOffset: 1 },
  { frequency: 1.2, speed: 7.5, amplitudeScale: 0.75, phaseOffset: 1.5, lineWidth: 1.2, glowWidth: 5.0, glowOpacity: 0.25, historyOffset: 2 },
  { frequency: 2.0, speed: 4.8, amplitudeScale: 0.65, phaseOffset: 2.1, lineWidth: 1.0, glowWidth: 4.0, glowOpacity: 0.2,  historyOffset: 3 },
  { frequency: 2.4, speed: 3.8, amplitudeScale: 0.55, phaseOffset: 2.8, lineWidth: 1.0, glowWidth: 4.0, glowOpacity: 0.2,  historyOffset: 4 },
  { frequency: 0.9, speed: 8.0, amplitudeScale: 0.45, phaseOffset: 3.3, lineWidth: 1.0, glowWidth: 3.0, glowOpacity: 0.15, historyOffset: 5 },
  { frequency: 1.6, speed: 5.5, amplitudeScale: 0.35, phaseOffset: 3.9, lineWidth: 0.8, glowWidth: 3.0, glowOpacity: 0.15, historyOffset: 6 },
  { frequency: 2.8, speed: 3.5, amplitudeScale: 0.25, phaseOffset: 4.5, lineWidth: 0.8, glowWidth: 2.0, glowOpacity: 0.1,  historyOffset: 7 },
];

// ── Color gradient (blue → violet → magenta → cyan) ────────────────
const GRADIENT_STOPS = [
  { pos: 0.00, color: "rgb(20, 61, 179)" },
  { pos: 0.30, color: "rgb(79, 61, 255)" },
  { pos: 0.55, color: "rgb(161, 20, 199)" },
  { pos: 0.95, color: "rgb(41, 161, 255)" },
];

const IDLE_AMPLITUDE = 0.01;

export function WaveformVisualizer({
  levelsRef,
  isActive,
  height = 120,
}: WaveformVisualizerProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const animFrameRef = useRef<number>(0);
  const smoothedRef = useRef(new Float32Array(WAVES.length).fill(IDLE_AMPLITUDE));
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

    const draw = (time: number) => {
      const t = time / 1000;
      const levels = levelsRef.current;
      const active = isActiveRef.current;
      const smoothed = smoothedRef.current;

      // ── Update per-wave audio levels ──
      for (let i = 0; i < WAVES.length; i++) {
        const cfg = WAVES[i];
        let target = IDLE_AMPLITUDE;

        if (active && levels && levels.length > 0) {
          const end = Math.max(0, levels.length - cfg.historyOffset);
          if (end > 0) {
            const count = Math.min(end, 4);
            const start = end - count;
            let sum = 0;
            for (let j = start; j < end; j++) sum += levels[j];
            const peak = Math.max(...levels.slice(start, end));
            const avg = sum / count;
            // Emphasize peaks for dynamic response
            target = Math.max(peak * 0.8 + avg * 0.2, IDLE_AMPLITUDE);
          }
        }

        const delta = target - smoothed[i];
        // Faster attack, slower release
        smoothed[i] += delta * (delta > 0 ? 0.2 : 0.05);
      }

      // ── Canvas ──
      const dpr = window.devicePixelRatio || 1;
      const w = canvas.width / dpr;
      const h = height;
      
      ctx.clearRect(0, 0, w, h);

      const midX = w / 2;
      const midY = h / 2;
      const padding = Math.min(Math.max(4, midY * 0.15), 16);
      const maxAmp = midY - padding;

      if (maxAmp <= 1) {
        animFrameRef.current = requestAnimationFrame(draw);
        return;
      }

      // ── Animated Gradient ──
      const gradientOffset = Math.sin(t * 0.5) * 0.1;
      const gradient = ctx.createLinearGradient(0, 0, w, 0);
      for (const stop of GRADIENT_STOPS) {
        const loc = Math.max(0, Math.min(1, stop.pos + gradientOffset));
        gradient.addColorStop(loc, stop.color);
      }

      ctx.globalCompositeOperation = "lighter";
      ctx.strokeStyle = gradient;
      ctx.lineCap = "round";
      ctx.lineJoin = "round";

      // Draw back to front
      for (let i = WAVES.length - 1; i >= 0; i--) {
        const cfg = WAVES[i];
        const wavePhase = -(t * cfg.speed) + cfg.phaseOffset;
        // Organic micro-movement
        const wobble = 0.88 + 0.12 * Math.sin(t * 3.0 + i * 1.7);
        const level = Math.max(0.01, smoothed[i] * cfg.amplitudeScale * wobble);

        ctx.beginPath();
        const step = 2; // Optimization: skip pixels for performance
        
        for (let x = 0; x <= w; x += step) {
          const normalized = (x - midX) / midX;
          // Gaussian envelope for soft edges
          const envelope = Math.exp(-Math.pow(normalized * 2.5, 2));
          
          const y = midY + envelope * maxAmp * level * Math.sin(2 * Math.PI * (x / w) * cfg.frequency + wavePhase);
          
          if (x === 0) ctx.moveTo(x, y);
          else ctx.lineTo(x, y);
        }

        const opacity = i === 0 ? 0.9 : Math.min(0.8, 0.3 + (1.0 - i / WAVES.length) * 0.5);

        // Glow pass (thick line, low opacity)
        ctx.lineWidth = cfg.glowWidth;
        ctx.globalAlpha = cfg.glowOpacity;
        ctx.stroke();

        // Core pass (thin line, high opacity)
        ctx.lineWidth = cfg.lineWidth;
        ctx.globalAlpha = opacity;
        ctx.stroke();
      }

      // Reset for next frame
      ctx.globalAlpha = 1.0;
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
