import { afterEach, expect, it, vi } from "vitest";
import { act } from "react";
import { createRoot } from "react-dom/client";
import { WaveformVisualizer } from "../WaveformVisualizer";

class TestPath {
  points: number[][] = [];
  moveTo(x: number, y: number) { this.points.push([x, y]); }
  lineTo(x: number, y: number) { this.points.push([x, y]); }
}
afterEach(() => { vi.restoreAllMocks(); vi.unstubAllGlobals(); });
it("plots real amplitude, flat silence, bounded compact waves and no movement while inactive", async () => {
  let draw: FrameRequestCallback = () => {};
  let paths: TestPath[] = [];
  vi.stubGlobal("Path2D", TestPath);
  vi.stubGlobal("ResizeObserver", class { observe() {} disconnect() {} });
  vi.stubGlobal("requestAnimationFrame", (callback: FrameRequestCallback) => { draw = callback; return 1; });
  vi.stubGlobal("cancelAnimationFrame", () => {});
  const motion = { matches: false };
  vi.stubGlobal("matchMedia", () => motion);
  vi.spyOn(HTMLCanvasElement.prototype, "getContext").mockReturnValue({
    setTransform() {}, clearRect() { paths = []; },
    createLinearGradient() { return { addColorStop() {} }; }, save() {}, restore() {},
    stroke(path: TestPath) { paths.push(path); },
  } as unknown as CanvasRenderingContext2D);
  const container = document.createElement("div");
  Object.defineProperty(container, "clientWidth", { value: 600 });
  const root = createRoot(container), levelsRef = { current: new Array(90).fill(0) }, bandsRef = { current: [] as number[] };
  await act(async () => root.render(<WaveformVisualizer levelsRef={levelsRef} bandsRef={bandsRef} isActive height={240} />));
  draw(performance.now());
  const extent = () => Math.max(...paths.flatMap(path => path.points.map(point => Math.abs(point[1] - 120))));
  expect(extent()).toBe(0);
  levelsRef.current.fill(.1); draw(performance.now() + 33); const soft = extent();
  levelsRef.current.fill(.9); draw(performance.now() + 66);
  expect(extent()).toBeGreaterThan(soft * 5);
  motion.matches = true;
  levelsRef.current.fill(.3); draw(performance.now() + 70);
  const speech = extent();
  expect(speech).toBeGreaterThan(18); // Previously ~10 px: normal speech was attenuated twice.
  draw(performance.now() + 74);
  expect(extent()).toBe(speech); // Reduced motion freezes travel, not audio responsiveness.
  levelsRef.current.fill(.8); draw(performance.now() + 78);
  expect(extent()).toBeGreaterThan(speech * 2);
  // Frequency data must not suppress loudness, or make all strands identical.
  levelsRef.current.fill(.6);
  bandsRef.current = [0,0,0,0,0,0,0]; draw(performance.now() + 80);
  expect(extent()).toBeGreaterThan(35);
  bandsRef.current = [.8,0,0,0,0,0,0]; draw(performance.now() + 80);
  const lowPaths = paths.map(path => path.points.map(point => point[1]));
  bandsRef.current = [0,0,0,0,0,0,.8]; draw(performance.now() + 80);
  expect(paths.map(path => path.points.map(point => point[1]))).not.toEqual(lowPaths);
  expect(extent()).toBeGreaterThan(35);
  expect(paths.at(-1)!.points.map(point => point[1])).toEqual(lowPaths.at(-1)); // Reduced Motion keeps peak positions fixed.
  levelsRef.current.fill(0); draw(performance.now() + 80);
  expect(extent()).toBe(0); // A stale spectrum cannot keep silence moving.
  bandsRef.current = [];
  // The first speech sample must be visible without waiting for history to fill.
  motion.matches = false;
  levelsRef.current = [0.5]; draw(performance.now() + 82);
  expect(extent()).toBeGreaterThan(10);
  await act(async () => root.render(<WaveformVisualizer levelsRef={levelsRef} isActive={false} height={240} />));
  draw(performance.now() + 99); expect(extent()).toBe(0);
  await act(async () => root.render(<WaveformVisualizer levelsRef={levelsRef} bandsRef={bandsRef} isActive height={40} />));
  draw(performance.now() + 132);
  expect(paths.flatMap(path => path.points).every(([x,y]) => x >= 0 && x <= 600 && y >= 0 && y <= 40)).toBe(true);
  levelsRef.current = new Array(90).fill(1); draw(performance.now() + 165);
  expect(paths.flatMap(path => path.points).every(([,y]) => y >= 0 && y <= 40)).toBe(true);
  bandsRef.current = [0,0,0,0,0,0,.8]; draw(performance.now() + 198);
  expect(paths[3].points.some(([, y]) => Math.abs(y - 20) > 1)).toBe(true); // Highest band reaches a widget strand.
  expect(paths.flatMap(path => path.points).every(([,y]) => y >= 0 && y <= 40)).toBe(true);
  await act(async () => root.unmount());
});
