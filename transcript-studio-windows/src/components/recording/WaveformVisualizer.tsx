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

const WAVES: WaveConfig[] = [
  // Background glow layers (wide, blurred)
  { freq: 1.2, amp: 0.28, phase: 0.0, speed: 0.6, color: "rgba(0, 194, 255, 0.12)", lineWidth: 8, blur: 12 },
  { freq: 1.5, amp: 0.22, phase: 1.2, speed: 0.8, color: "rgba(229, 0, 116, 0.08)", lineWidth: 6, blur: 10 },

  // Mid layers
  { freq: 1.0, amp: 0.32, phase: 0.5, speed: 0.5, color: "rgba(0, 194, 255, 0.15)", lineWidth: 3, blur: 4 },
  { freq: 1.8, amp: 0.18, phase: 2.0, speed: 0.9, color: "rgba(115, 89, 243, 0.12)", lineWidth: 2.5, blur: 3 },

  // Sharp foreground waves
  { freq: 1.3, amp: 0.30, phase: 0.0, speed: 0.7, color: "rgba(0, 194, 255, 0.65)", lineWidth: 2.0, blur: 0 },
  { freq: 1.6, amp: 0.22, phase: 1.0, speed: 0.85, color: "rgba(89, 115, 230, 0.55)", lineWidth: 1.8, blur: 0 },
  { freq: 2.0, amp: 0.15, phase: 2.5, speed: 1.1, color: "rgba(140, 77, 217, 0.45)", lineWidth: 1.5, blur: 0 },
  { freq: 1.1, amp: 0.25, phase: 3.5, speed: 0.55, color: "rgba(229, 0, 116, 0.30)", lineWidth: 1.5, blur: 0 },
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

    // Smooth the level for organic feel
    const targetLevel = isPaused ? 5 : Math.max(5, level);
    smoothLevelRef.current += (targetLevel - smoothLevelRef.current) * 0.15;
    const currentLevel = smoothLevelRef.current / 100;

    const draw = (time: number) => {
      const { width, height: h } = canvas;
      ctx.clearRect(0, 0, width, h);

      const timeSec = time / 1000;

      for (const wave of WAVES) {
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
          // Envelope: taper at edges
          const envelope = Math.sin(progress * Math.PI);
          const envShaped = Math.pow(envelope, 0.8);

          // Composite sine
          const phase1 = progress * wave.freq * 2 * Math.PI + timeSec * wave.speed + wave.phase;
          const phase2 = progress * wave.freq * 1.3 * Math.PI + timeSec * wave.speed * 0.7 + wave.phase * 1.5;
          const waveVal = Math.sin(phase1) * 0.7 + Math.sin(phase2) * 0.3;

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
