import { useEffect, useRef } from "react";

interface WaveformVisualizerProps {
  level: number; // 0–100
  isPaused: boolean;
  height?: number;
}

interface WaveConfig {
  freq: number;
  amp: number;
  phase: number;
  speed: number;
  color: string;
  lineWidth: number;
  blur: number;
}

// Layer 1: Deep background glow (very wide, heavy blur)
const GLOW_WAVES: WaveConfig[] = [
  { freq: 0.6, amp: 0.35, phase: 0.0, speed: 0.3, color: "rgba(13, 26, 153, 0.18)", lineWidth: 18, blur: 28 },
  { freq: 0.8, amp: 0.30, phase: 1.5, speed: 0.4, color: "rgba(38, 13, 140, 0.15)", lineWidth: 14, blur: 22 },
  { freq: 1.0, amp: 0.28, phase: 0.8, speed: 0.35, color: "rgba(0, 115, 217, 0.12)", lineWidth: 12, blur: 20 },
];

// Layer 2: Mid glow (moderate blur, richer colors)
const MID_WAVES: WaveConfig[] = [
  { freq: 1.2, amp: 0.32, phase: 0.0, speed: 0.55, color: "rgba(0, 153, 255, 0.18)", lineWidth: 7, blur: 10 },
  { freq: 1.5, amp: 0.25, phase: 1.2, speed: 0.7, color: "rgba(102, 38, 230, 0.14)", lineWidth: 6, blur: 8 },
  { freq: 0.9, amp: 0.30, phase: 2.5, speed: 0.45, color: "rgba(0, 194, 255, 0.16)", lineWidth: 5, blur: 7 },
  { freq: 1.8, amp: 0.20, phase: 0.3, speed: 0.8, color: "rgba(179, 0, 153, 0.10)", lineWidth: 5, blur: 6 },
];

// Layer 3: Sharp foreground waves (no blur, vivid)
const SHARP_WAVES: WaveConfig[] = [
  { freq: 1.0, amp: 0.34, phase: 0.0, speed: 0.5, color: "rgba(0, 179, 255, 0.70)", lineWidth: 2.2, blur: 0 },
  { freq: 1.3, amp: 0.28, phase: 0.8, speed: 0.65, color: "rgba(51, 102, 255, 0.60)", lineWidth: 2.0, blur: 0 },
  { freq: 1.6, amp: 0.22, phase: 1.5, speed: 0.80, color: "rgba(115, 64, 242, 0.55)", lineWidth: 1.8, blur: 0 },
  { freq: 2.0, amp: 0.16, phase: 2.2, speed: 1.0, color: "rgba(140, 38, 217, 0.50)", lineWidth: 1.5, blur: 0 },
  { freq: 1.1, amp: 0.30, phase: 3.0, speed: 0.55, color: "rgba(0, 140, 242, 0.55)", lineWidth: 1.8, blur: 0 },
  { freq: 1.7, amp: 0.18, phase: 4.0, speed: 0.90, color: "rgba(204, 0, 128, 0.35)", lineWidth: 1.5, blur: 0 },
];

// Layer 4: Bright accent highlights (thin, high-frequency shimmer)
const ACCENT_WAVES: WaveConfig[] = [
  { freq: 2.4, amp: 0.12, phase: 0.5, speed: 1.3, color: "rgba(0, 230, 255, 0.45)", lineWidth: 1.2, blur: 0 },
  { freq: 2.8, amp: 0.10, phase: 1.8, speed: 1.5, color: "rgba(179, 77, 255, 0.35)", lineWidth: 1.0, blur: 0 },
  { freq: 3.2, amp: 0.08, phase: 3.2, speed: 1.7, color: "rgba(230, 0, 115, 0.30)", lineWidth: 0.8, blur: 0 },
];

const ALL_WAVES: WaveConfig[] = [
  ...GLOW_WAVES,
  ...MID_WAVES,
  ...SHARP_WAVES,
  ...ACCENT_WAVES,
];

export function WaveformVisualizer({
  level,
  isPaused,
  height = 48,
}: WaveformVisualizerProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const animFrameRef = useRef<number>(0);
  const smoothLevelRef = useRef<number>(0);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    const draw = (time: number) => {
      const targetLevel = isPaused ? 5 : Math.max(5, level);
      smoothLevelRef.current +=
        (targetLevel - smoothLevelRef.current) * 0.15;
      const currentLevel = smoothLevelRef.current / 100;

      const { width, height: h } = canvas;
      ctx.clearRect(0, 0, width, h);

      const timeSec = time / 1000;

      for (const wave of ALL_WAVES) {
        ctx.save();

        if (wave.blur > 0) {
          ctx.filter = `blur(${wave.blur}px)`;
        }

        ctx.strokeStyle = wave.color;
        ctx.lineWidth = wave.lineWidth;
        ctx.lineCap = "round";
        ctx.lineJoin = "round";
        ctx.beginPath();

        const midY = h / 2;
        const amplitude = h * wave.amp * currentLevel;
        const steps = width;

        for (let x = 0; x <= steps; x++) {
          const progress = x / steps;

          // Envelope: smooth taper at edges with steeper falloff
          const envelope = Math.sin(progress * Math.PI);
          const envShaped = Math.pow(envelope, 0.65);

          // Triple-harmonic composite for complex organic motion
          const phase1 =
            progress * wave.freq * 2 * Math.PI +
            timeSec * wave.speed +
            wave.phase;
          const phase2 =
            progress * wave.freq * 1.3 * Math.PI +
            timeSec * wave.speed * 0.7 +
            wave.phase * 1.5;
          const phase3 =
            progress * wave.freq * 3.1 * Math.PI +
            timeSec * wave.speed * 1.3 +
            wave.phase * 0.8;
          const waveVal =
            Math.sin(phase1) * 0.55 +
            Math.sin(phase2) * 0.30 +
            Math.sin(phase3) * 0.15;

          const y = midY + waveVal * amplitude * envShaped;

          if (x === 0) {
            ctx.moveTo(x, y);
          } else {
            ctx.lineTo(x, y);
          }
        }

        ctx.stroke();
        ctx.restore();
      }

      animFrameRef.current = requestAnimationFrame(draw);
    };

    animFrameRef.current = requestAnimationFrame(draw);
    return () => cancelAnimationFrame(animFrameRef.current);
  }, [level, isPaused]);

  return (
    <canvas
      ref={canvasRef}
      width={400}
      height={height * 2}
      style={{ width: "100%", height }}
    />
  );
}
