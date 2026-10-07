import { useEffect, useRef } from "react";
import { HISTORY_SIZE } from "../../hooks/useAudioLevel";

interface WaveformVisualizerProps {
  levelsRef: React.RefObject<number[]>;
  isActive: boolean;
  height?: number;
  strands?: number;
}
// macOS WaveConfig: three delayed gaussian lobes, shared carrier origin and
// light-thread ribbon. Rust supplies the gated envelope; silence stays flat.
const TAU = 2 * Math.PI;
const LINES = [
  { width: .7, alpha: .44, k: .76, phase: -.90, offset: -1, main: false },
  { width: .9, alpha: .68, k: .88, phase: -.51, offset: -.65, main: false },
  { width: 1.1, alpha: .80, k: .96, phase: -.23, offset: -.31, main: false },
  { width: 1.1, alpha: .80, k: .96, phase: .24, offset: .31, main: false },
  { width: .9, alpha: .68, k: .88, phase: .54, offset: .65, main: false },
  { width: .7, alpha: .44, k: .76, phase: .94, offset: 1, main: false },
  { width: 2.2, alpha: 1, k: 1, phase: 0, offset: 0, main: true },
];
const BELLIES = [
  { c: .31, w: .16, delay: 0, f: .037, amp: 1 },
  { c: .53, w: .15, delay: 70, f: .053, amp: .95 },
  { c: .73, w: .15, delay: 140, f: .071, amp: .78 },
];
const visualEnergy = (level: number) => .72 * Math.pow(Math.max(0, Math.min(1, level || 0)), 1.35);

export function WaveformVisualizer({ levelsRef, isActive, height = 240, strands }: WaveformVisualizerProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const activeRef = useRef(isActive);
  activeRef.current = isActive;
  useEffect(() => {
    const canvas = canvasRef.current;
    const ctx = canvas?.getContext("2d");
    if (!canvas || !ctx) return;
    let width = 0, frame = 0, last = performance.now(), time = 0, travel = 0, idleDrawn = false;
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)");
    const compact = height < 64;
    const lines = compact ? [LINES[1], LINES[2], LINES[4], LINES[6]] : LINES;
    const selected = strands ? [...lines.filter(l => !l.main).slice(0, Math.max(0, strands - 1)), LINES[6]] : lines;
    const resize = () => {
      width = canvas.parentElement?.clientWidth ?? 0;
      const dpr = window.devicePixelRatio || 1;
      canvas.width = Math.round(width * dpr);
      canvas.height = Math.round(height * dpr);
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      idleDrawn = false;
    };
    const observer = new ResizeObserver(resize);
    if (canvas.parentElement) observer.observe(canvas.parentElement);
    resize();
    const draw = (now: number) => {
      // Hidden window, or an inactive wave that is already on screen: nothing changes.
      if (document.hidden || (!activeRef.current && idleDrawn)) {
        last = now;
        frame = requestAnimationFrame(draw);
        return;
      }
      const dt = Math.max(0, Math.min(.064, (now - last) / 1000));
      last = now;
      const raw = activeRef.current ? levelsRef.current.slice(-HISTORY_SIZE) : [];
      const history = [...new Array(Math.max(0, HISTORY_SIZE - raw.length)).fill(0), ...raw];
      const live = history[history.length - 1] ?? 0;
      const level = visualEnergy(live);
      if (!reduced.matches && activeRef.current && !document.hidden) {
        time += dt;
        travel += dt * TAU * .3 * (1 + .25 * live);
      }
      const drift = reduced.matches ? 0 : time, phase = reduced.matches ? 0 : travel;
      const sample = (delay: number) => {
        const f = Math.max(0, history.length - 1 - delay / (1000 / 30));
        const i = Math.floor(f), u = f - i;
        return history[i] * (1 - u) + history[Math.min(history.length - 1, i + 1)] * u;
      };
      const bellies = BELLIES.map((b, i) => ({
        c: b.c + .04 * Math.sin(TAU * b.f * drift + i * 2.1),
        w: b.w * (1 + .2 * Math.sin(TAU * b.f * .83 * drift + i * 1.3)),
        amp: b.amp * (reduced.matches ? level : visualEnergy(sample(b.delay))),
      }));
      ctx.clearRect(0, 0, width, height);
      const gradient = (main: boolean) => {
        const g = ctx.createLinearGradient(0, 0, width, 0);
        const stops: [number, string][] = main
          ? [[0, "#f557d600"], [.08, "#f557d6b3"], [.27, "#ff6ee8"], [.36, "#ffc4ff"], [.47, "#bf70ff"], [.64, "#e3b3ff"], [.79, "#8778ff"], [1, "#5c87ff00"]]
          : [[0, "#f040c400"], [.08, "#f040c4b3"], [.25, "#f54de0"], [.51, "#b863fa"], [.77, "#9166ff"], [.92, "#5c87ffb3"], [1, "#5c87ff00"]];
        stops.forEach(([stop, color]) => g.addColorStop(stop, color));
        return g;
      };
      const cy = height / 2, maxH = height * .4 * (compact ? .7 : 1);
      const steps = Math.max(1, Math.ceil(width / (compact ? .5 : 2)));
      selected.forEach((line, j) => {
        const path = new Path2D();
        for (let p = 0; p <= steps; p++) {
          const x = p / steps, taper = Math.pow(Math.max(0, Math.sin(Math.PI * x)), 1.1);
          let sum = 0, spread = 0, weight = 0;
          bellies.forEach((b, i) => {
            const belly = Math.exp(-.5 * Math.pow((x - b.c) / b.w, 2));
            const gain = line.main ? 1 : 1 + .18 * Math.sin((j + 1) * (i + 2) * 1.3);
            weight += belly;
            sum += b.amp * line.k * gain * belly * Math.sin(TAU * 3 * x - phase + i * .35 + line.phase * (1 + i * .7));
            spread += b.amp * belly * (i === 1 ? -.8 : 1);
          });
          const y = cy - (sum / Math.max(1, weight) * maxH * taper + maxH * level * line.offset * .4 * spread * taper);
          if (!p) path.moveTo(x * width, y); else path.lineTo(x * width, y);
        }
        ctx.lineCap = "round"; ctx.lineJoin = "round";
        ctx.strokeStyle = gradient(line.main);
        if (line.main || (j >= 1 && j <= 4)) {
          ctx.save(); ctx.globalCompositeOperation = "lighter";
          ctx.globalAlpha = (line.main ? .75 : .25) * (.1 + .9 * Math.min(1, level / .3));
          ctx.filter = `blur(${compact ? 3 : line.main ? 16 : 7}px)`;
          ctx.lineWidth = compact ? 5 : line.main ? 20 : 8;
          ctx.stroke(path); ctx.restore();
        }
        ctx.globalAlpha = line.main ? 1 : line.alpha * (.55 + .45 * Math.min(1, level * 2));
        ctx.lineWidth = line.width * (compact ? .72 : 1);
        ctx.stroke(path);
      });
      ctx.globalAlpha = 1;
      idleDrawn = !activeRef.current;
      frame = requestAnimationFrame(draw);
    };
    frame = requestAnimationFrame(draw);
    return () => { cancelAnimationFrame(frame); observer.disconnect(); };
  }, [height, strands, levelsRef]);
  return <canvas ref={canvasRef} aria-hidden="true" style={{ display: "block", width: "100%", height }} />;
}
