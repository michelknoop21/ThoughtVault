import { useEffect, useRef } from "react";
import { HISTORY_SIZE } from "../../hooks/useAudioLevel";
import { useSettingsStore } from "../../stores/settingsStore";

interface WaveformVisualizerProps {
  levelsRef: React.RefObject<number[]>;
  bandsRef?: React.RefObject<number[]>;
  isActive: boolean;
  height?: number;
  strands?: number;
}
// SiriWave Classic curve adapted from kopiro/siriwave (MIT).
// License: docs/licenses/siriwave-MIT.txt. Keep geometry in sync with WaveConfig.
const TAU = 2 * Math.PI;
const LINES = [
  { width: .7, alpha: .44, k: .76, phase: -.90, main: false },
  { width: .9, alpha: .68, k: .88, phase: -.51, main: false },
  { width: 1.1, alpha: .80, k: .96, phase: -.23, main: false },
  { width: 1.1, alpha: .80, k: .96, phase: .24, main: false },
  { width: .9, alpha: .68, k: .88, phase: .54, main: false },
  { width: .7, alpha: .44, k: .76, phase: .94, main: false },
  { width: 2.2, alpha: 1, k: 1, phase: 0, main: true },
];
// The native envelope already gates noise and shapes the response. Preserve
// its dynamics instead of attenuating quiet speech a second time.
const visualEnergy = (level: number) => .9 * Math.max(0, Math.min(1, Number.isFinite(level) ? level : 0));

function siriwaveDisplacement(x: number, amplitude: number, gain: number, travel: number,
  index: number, frequency: number, line: typeof LINES[number], frozen: boolean) {
  const graphX = 4 * x - 2;
  const attenuation = Math.pow(4 / (4 + Math.pow(graphX, 4)), 4);
  const strandGain = line.main ? 1 : .25 + .75 * gain;
  const speed = line.main ? 1 : .82 + index * .065;
  const phase = frozen ? 0 : travel * speed;
  return attenuation * amplitude * line.k * strandGain * Math.sin(frequency * graphX - phase + line.phase);
}

export function WaveformVisualizer({ levelsRef, bandsRef, isActive, height = 240, strands }: WaveformVisualizerProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const activeRef = useRef(isActive);
  // Resizing the studio must not restart the travelling crests.
  const clock = useRef({ travel: 0, last: null as number | null });
  activeRef.current = isActive;
  useEffect(() => { clock.current.last = null; }, [isActive]);
  useEffect(() => {
    const canvas = canvasRef.current;
    const ctx = canvas?.getContext("2d");
    if (!canvas || !ctx) return;
    let width = 0, frame = 0, idleDrawn = false;
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)");
    // Other WebViews (the floating widget) share the saved preference.
    const syncMotion = (event: StorageEvent) => {
      if (event.key === "settings-store") void useSettingsStore.persist.rehydrate();
    };
    window.addEventListener("storage", syncMotion);
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
        clock.current.last = null;
        frame = requestAnimationFrame(draw);
        return;
      }
      const dt = clock.current.last === null ? 0 : Math.max(0, Math.min(.064, (now - clock.current.last) / 1000));
      const motion = useSettingsStore.getState().waveform_motion ?? "system";
      const frozen = motion === "reduced" || (motion === "system" && reduced.matches);
      clock.current.last = frozen ? null : now;
      const raw = activeRef.current ? levelsRef.current.slice(-HISTORY_SIZE) : [];
      const history = [...new Array(Math.max(0, HISTORY_SIZE - raw.length)).fill(0), ...raw];
      const live = history[history.length - 1] ?? 0;
      const bands = activeRef.current ? (bandsRef?.current ?? []).map(value => Number.isFinite(value) ? Math.max(0, Math.min(1, value)) : 0) : [];
      const level = visualEnergy(live);
      const peakBand = Math.max(0, ...bands);
      if (!frozen && activeRef.current && !document.hidden) {
        clock.current.travel += dt * TAU * .65 * (1 + .8 * level / .9);
      }
      const travel = clock.current.travel;
      const sample = (delay: number) => {
        const f = Math.max(0, history.length - 1 - delay / (1000 / 30));
        const i = Math.floor(f), u = f - i;
        return history[i] * (1 - u) + history[Math.min(history.length - 1, i + 1)] * u;
      };
      ctx.clearRect(0, 0, width, height);
      const gradient = (main: boolean) => {
        const g = ctx.createLinearGradient(0, 0, width, 0);
        const stops: [number, string][] = main
          ? [[0, "rgb(96% 34% 84% / 0)"], [.08, "rgb(96% 34% 84% / .7)"], [.27, "rgb(100% 43% 91%)"], [.36, "rgb(100% 77% 100%)"], [.47, "rgb(75% 44% 100%)"], [.64, "rgb(89% 70% 100%)"], [.79, "rgb(53% 47% 100%)"], [1, "rgb(36% 53% 100% / 0)"]]
          : [[0, "rgb(94% 25% 77% / 0)"], [.08, "rgb(94% 25% 77% / .7)"], [.25, "rgb(96% 30% 88%)"], [.51, "rgb(72% 39% 98%)"], [.77, "rgb(57% 40% 100%)"], [.92, "rgb(36% 53% 100% / .7)"], [1, "rgb(36% 53% 100% / 0)"]];
        stops.forEach(([stop, color]) => g.addColorStop(stop, color));
        return g;
      };
      const cy = height / 2, maxH = height * .4;
      const steps = Math.max(1, Math.ceil(width / (compact ? .5 : 2)));
      selected.forEach((line, j) => {
        const bandIndex = Math.min(bands.length - 1, Math.floor(j * bands.length / Math.max(1, selected.length - 1)));
        const bandEnd = Math.min(bands.length, Math.max(bandIndex + 1, Math.floor((j + 1) * bands.length / Math.max(1, selected.length - 1))));
        const gain = line.main || !bands.length ? 1 : peakBand > 0 ? Math.max(...bands.slice(bandIndex, bandEnd)) / peakBand : 0;
        const frequency = frozen ? 3.4 : line.main ? 3.4 : 2.8 + Math.max(0, bandIndex) * .22;
        const delayed = frozen ? level : visualEnergy(sample(j * 25));
        const amplitude = level === 0 ? 0 : line.main ? level : .65 * level + .35 * delayed;
        const path = new Path2D();
        for (let p = 0; p <= steps; p++) {
          const x = p / steps;
          const y = cy - maxH * siriwaveDisplacement(x, amplitude, gain, travel, j, frequency, line, frozen);
          if (!p) path.moveTo(x * width, y); else path.lineTo(x * width, y);
        }
        ctx.lineCap = "round"; ctx.lineJoin = "round";
        ctx.strokeStyle = gradient(line.main);
        if (line.main || (j >= 1 && j <= 4)) {
          ctx.save(); ctx.globalCompositeOperation = "lighter";
          ctx.globalAlpha = (line.main ? .75 : (j === 2 || j === 3 ? .32 : .20)) * (.1 + .9 * Math.min(1, level / .3));
          ctx.filter = `blur(${compact ? 3 : line.main ? 10 : 7}px)`;
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
    return () => { cancelAnimationFrame(frame); observer.disconnect(); window.removeEventListener("storage", syncMotion); };
  }, [height, strands, levelsRef, bandsRef]);
  return <canvas ref={canvasRef} aria-hidden="true" style={{ display: "block", width: "100%", height }} />;
}
