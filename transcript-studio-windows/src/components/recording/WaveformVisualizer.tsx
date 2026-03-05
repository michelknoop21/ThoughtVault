import { useEffect, useRef } from "react";

interface WaveformVisualizerProps {
  level: number; // 0–100
  isPaused: boolean;
  height?: number;
  barCount?: number;
  color?: string;
}

export function WaveformVisualizer({
  level,
  isPaused,
  height = 48,
  barCount = 32,
  color = "rgba(229, 0, 116, 0.85)",
}: WaveformVisualizerProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const historyRef = useRef<number[]>(new Array(barCount).fill(0));
  const animFrameRef = useRef<number>(0);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    // Push new level into history, shift old values
    historyRef.current.push(isPaused ? 0 : level / 100);
    if (historyRef.current.length > barCount) {
      historyRef.current.shift();
    }

    const draw = () => {
      const { width, height: h } = canvas;
      ctx.clearRect(0, 0, width, h);

      const barWidth = (width / barCount) * 0.6;
      const gap = (width / barCount) * 0.4;

      historyRef.current.forEach((val, i) => {
        const barHeight = Math.max(2, val * h * 0.9);
        const x = i * (barWidth + gap);
        const y = (h - barHeight) / 2;

        // Fade older bars
        const alpha = 0.3 + (i / barCount) * 0.7;
        ctx.fillStyle = color.replace("0.85", alpha.toFixed(2));
        ctx.beginPath();
        ctx.roundRect(x, y, barWidth, barHeight, 2);
        ctx.fill();
      });
    };

    animFrameRef.current = requestAnimationFrame(draw);
    return () => cancelAnimationFrame(animFrameRef.current);
  }, [level, isPaused, barCount, color]);

  return (
    <canvas
      ref={canvasRef}
      width={200}
      height={height}
      style={{ width: "100%", height }}
    />
  );
}
