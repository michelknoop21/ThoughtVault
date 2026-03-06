import { useEffect, useRef } from "react";

interface WaveformVisualizerProps {
  level: number; // 0–100
  isPaused: boolean;
  height?: number;
}

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

    // Resize canvas to match container
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

    // Colors
    const neonBlue = "rgba(0, 204, 255, 0.5)";
    const deepPurple = "rgba(102, 51, 255, 0.45)";
    const brightMagenta = "rgba(230, 0, 255, 0.4)";
    const cyanHighlight = "rgba(51, 255, 230, 0.6)";

    const draw = (time: number) => {
      const targetLevel = isPaused ? 2 : Math.max(level, 2);
      const delta = targetLevel - smoothLevelRef.current;
      smoothLevelRef.current += delta * (delta > 0 ? 0.30 : 0.14);
      const currentLevel = Math.pow(Math.max(0, smoothLevelRef.current) / 100, 0.52);

      const w = canvas.style.width ? parseFloat(canvas.style.width) : canvas.width;
      const h = height;
      ctx.clearRect(0, 0, w, h);

      const timeSec = time / 1000;

      // 1. Background Glows
      ctx.save();
      ctx.globalCompositeOperation = "screen";
      const glowConfigs = [
        { color: "rgba(102, 51, 255, 0.12)", blur: 30, amp: 0.45, freq: 0.4, speed: 0.25 },
        { color: "rgba(0, 204, 255, 0.10)",  blur: 24, amp: 0.40, freq: 0.6, speed: 0.35 },
        { color: "rgba(230, 0, 255, 0.08)", blur: 35, amp: 0.35, freq: 0.3, speed: 0.20 },
      ];

      for (const glow of glowConfigs) {
        ctx.filter = `blur(${glow.blur}px)`;
        drawWavePath(ctx, w, h, glow.freq, h * glow.amp * currentLevel, timeSec * glow.speed, 0.6);
        ctx.strokeStyle = glow.color;
        ctx.lineWidth = 35;
        ctx.stroke();
      }
      ctx.restore();

      // 2. Dense Neon Lines
      ctx.save();
      ctx.globalCompositeOperation = "lighter";
      const lineCount = 12;
      for (let i = 0; i < lineCount; i++) {
        const progress = i / lineCount;
        let color = neonBlue;
        if (progress > 0.33) color = deepPurple;
        if (progress > 0.66) color = brightMagenta;

        const freq = 0.8 + i * 0.12;
        const amp = (0.28 - i * 0.01) * h * currentLevel;
        const speed = 0.6 + i * 0.08;
        const phase = i * 0.45 + timeSec * speed;

        drawWavePath(ctx, w, h, freq, amp, phase, 0.85);
        ctx.strokeStyle = color;
        ctx.lineWidth = 1.0;
        ctx.stroke();
      }
      ctx.restore();

      // 3. Bright Core Lines
      ctx.save();
      ctx.globalCompositeOperation = "lighter";
      for (let i = 0; i < 3; i++) {
        const freq = 1.1 + i * 0.4;
        const amp = (0.16 - i * 0.03) * h * currentLevel;
        const phase = timeSec * (1.1 + i * 0.3) + i * 2.0;

        drawWavePath(ctx, w, h, freq, amp, phase, 1.3);
        ctx.strokeStyle = cyanHighlight;
        ctx.lineWidth = 0.8;
        ctx.stroke();
      }
      ctx.restore();

      // 4. White Center Core
      ctx.save();
      drawWavePath(ctx, w, h, 0.5, 0.05 * h * currentLevel, timeSec * 0.8, 1.8);
      ctx.strokeStyle = "rgba(255, 255, 255, 0.4)";
      ctx.lineWidth = 0.5;
      ctx.stroke();
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

    const w1 = Math.sin(xProgress * frequency * 2.0 * Math.PI + phase);
    const w2 = Math.sin(xProgress * frequency * 3.5 * Math.PI + phase * 0.7) * 0.3;
    const w3 = Math.sin(xProgress * frequency * 1.2 * Math.PI + phase * 1.4) * 0.2;
    const combinedWave = (w1 + w2 + w3) / 1.5;

    const px = (x / steps) * width;
    const y = midY + combinedWave * amplitude * envelope;

    if (x === 0) {
      ctx.moveTo(px, y);
    } else {
      ctx.lineTo(px, y);
    }
  }
}
