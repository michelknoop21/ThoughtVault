import { useEffect, useRef } from "react";

interface WaveformVisualizerProps {
  level: number; // 0–100
  isPaused: boolean;
  height?: number;
}

// Each wave has independent frequency, speed, smoothing and color
interface WaveLineConfig {
  frequency: number;
  speed: number;        // radians per second
  ampScale: number;     // fraction of max amplitude
  smoothUp: number;     // attack rate (0-1, higher = snappier)
  smoothDown: number;   // release rate
  phaseOffset: number;  // initial phase offset so waves start desynchronized
  color: string;
  lineWidth: number;
  envelopePower: number;
  blendMode: GlobalCompositeOperation;
}

const WAVE_LINES: WaveLineConfig[] = [
  // Primary bold wave — fastest attack
  { frequency: 1.5,  speed: 9.0,   ampScale: 0.28,  smoothUp: 0.40, smoothDown: 0.10, phaseOffset: 0.0,  color: "rgba(0, 204, 255, 0.65)",   lineWidth: 2.0, envelopePower: 0.85, blendMode: "lighter" },
  // Secondary waves — each with unique timing
  { frequency: 1.8,  speed: 7.2,   ampScale: 0.24,  smoothUp: 0.30, smoothDown: 0.08, phaseOffset: 1.2,  color: "rgba(102, 51, 255, 0.55)",  lineWidth: 1.2, envelopePower: 0.85, blendMode: "lighter" },
  { frequency: 1.2,  speed: 11.5,  ampScale: 0.22,  smoothUp: 0.20, smoothDown: 0.06, phaseOffset: 2.8,  color: "rgba(230, 0, 255, 0.50)",   lineWidth: 1.0, envelopePower: 0.85, blendMode: "lighter" },
  { frequency: 2.1,  speed: 5.8,   ampScale: 0.20,  smoothUp: 0.45, smoothDown: 0.12, phaseOffset: 4.1,  color: "rgba(51, 255, 230, 0.50)",  lineWidth: 1.0, envelopePower: 0.85, blendMode: "lighter" },
  { frequency: 0.9,  speed: 13.0,  ampScale: 0.18,  smoothUp: 0.15, smoothDown: 0.05, phaseOffset: 5.5,  color: "rgba(80, 40, 255, 0.40)",   lineWidth: 0.8, envelopePower: 0.85, blendMode: "lighter" },
  // Background glow waves — slow, wide, soft
  { frequency: 0.4,  speed: 2.5,   ampScale: 0.35,  smoothUp: 0.12, smoothDown: 0.04, phaseOffset: 0.5,  color: "rgba(102, 51, 255, 0.12)",  lineWidth: 30,  envelopePower: 0.6,  blendMode: "screen" },
  { frequency: 0.6,  speed: 3.5,   ampScale: 0.30,  smoothUp: 0.10, smoothDown: 0.03, phaseOffset: 3.0,  color: "rgba(0, 204, 255, 0.10)",   lineWidth: 24,  envelopePower: 0.6,  blendMode: "screen" },
  { frequency: 0.3,  speed: 2.0,   ampScale: 0.25,  smoothUp: 0.08, smoothDown: 0.03, phaseOffset: 1.8,  color: "rgba(230, 0, 255, 0.08)",   lineWidth: 30,  envelopePower: 0.6,  blendMode: "screen" },
];

export function WaveformVisualizer({
  level,
  isPaused,
  height = 48,
}: WaveformVisualizerProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const animFrameRef = useRef<number>(0);
  // One smoothed level per wave for independent amplitude response
  const smoothLevelsRef = useRef<number[]>(WAVE_LINES.map(() => 0));

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
      const w = parent.clientWidth;
      canvas.width = w * dpr;
      canvas.height = height * dpr;
      canvas.style.width = `${w}px`;
      canvas.style.height = `${height}px`;
      ctx!.setTransform(dpr, 0, 0, dpr, 0, 0);
    }
    resize();

    const observer = new ResizeObserver(resize);
    observer.observe(canvas.parentElement!);

    const draw = (time: number) => {
      const targetLevel = isPaused ? 2 : Math.max(level, 2);

      // Update each wave's smoothed level independently
      const levels = smoothLevelsRef.current;
      for (let i = 0; i < WAVE_LINES.length; i++) {
        const cfg = WAVE_LINES[i];
        const delta = targetLevel - levels[i];
        const rate = delta > 0 ? cfg.smoothUp : cfg.smoothDown;
        levels[i] += delta * rate;
      }

      const w = canvas.style.width ? parseFloat(canvas.style.width) : canvas.width;
      const h = height;
      ctx.clearRect(0, 0, w, h);

      const timeSec = time / 1000;

      // Draw glow waves first (last entries in config), then sharp lines on top
      // Sort: blendMode "screen" first, then "lighter"
      const glowIndices: number[] = [];
      const lineIndices: number[] = [];
      for (let i = 0; i < WAVE_LINES.length; i++) {
        if (WAVE_LINES[i].blendMode === "screen") glowIndices.push(i);
        else lineIndices.push(i);
      }

      // Glow layer
      ctx.save();
      ctx.globalCompositeOperation = "screen";
      for (const i of glowIndices) {
        const cfg = WAVE_LINES[i];
        const waveLevel = Math.pow(Math.max(0, levels[i]) / 100, 0.52);
        const phase = cfg.phaseOffset + timeSec * cfg.speed;
        ctx.filter = `blur(${Math.round(cfg.lineWidth)}px)`;
        drawWavePath(ctx, w, h, cfg.frequency, h * cfg.ampScale * waveLevel, phase, cfg.envelopePower);
        ctx.strokeStyle = cfg.color;
        ctx.lineWidth = cfg.lineWidth;
        ctx.stroke();
      }
      ctx.filter = "none";
      ctx.restore();

      // Sharp line layer
      ctx.save();
      ctx.globalCompositeOperation = "lighter";
      for (const i of lineIndices) {
        const cfg = WAVE_LINES[i];
        const waveLevel = Math.pow(Math.max(0, levels[i]) / 100, 0.52);
        const phase = cfg.phaseOffset + timeSec * cfg.speed;
        drawWavePath(ctx, w, h, cfg.frequency, h * cfg.ampScale * waveLevel, phase, cfg.envelopePower);
        ctx.strokeStyle = cfg.color;
        ctx.lineWidth = cfg.lineWidth;
        ctx.stroke();
      }
      ctx.restore();

      animFrameRef.current = requestAnimationFrame(draw);
    };

    animFrameRef.current = requestAnimationFrame(draw);
    return () => {
      cancelAnimationFrame(animFrameRef.current);
      observer.disconnect();
    };
  }, [level, isPaused, height]);

  return (
    <canvas
      ref={canvasRef}
      className="block w-full"
    />
  );
}

function drawWavePath(
  ctx: CanvasRenderingContext2D,
  width: number,
  height: number,
  frequency: number,
  amplitude: number,
  phase: number,
  envelopePower: number,
) {
  ctx.beginPath();
  const midY = height / 2;
  const steps = Math.max(width, 200);

  for (let x = 0; x <= steps; x++) {
    const xProgress = x / steps;
    const envelope = Math.pow(Math.sin(xProgress * Math.PI), envelopePower);

    const y = midY + Math.sin(2 * Math.PI * xProgress * frequency + phase) * amplitude * envelope;
    const px = xProgress * width;

    if (x === 0) {
      ctx.moveTo(px, y);
    } else {
      ctx.lineTo(px, y);
    }
  }
}
