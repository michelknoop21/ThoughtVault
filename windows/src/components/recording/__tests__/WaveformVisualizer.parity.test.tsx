import { afterEach, expect, it, vi } from "vitest";
import { act } from "react";
import { createRoot } from "react-dom/client";
import reference from "../../../../../tests/fixtures/waveform-reference.json";
import { WaveformVisualizer } from "../WaveformVisualizer";

class TestPath {
  points: number[][] = [];
  moveTo(x: number, y: number) { this.points.push([x, y]); }
  lineTo(x: number, y: number) { this.points.push([x, y]); }
}
afterEach(() => { vi.restoreAllMocks(); vi.unstubAllGlobals(); });

it("matches the unchanged Apple geometry at 30/60/120 Hz in studio and widget", async () => {
  let draw: FrameRequestCallback = () => {};
  let paths: TestPath[] = [];
  vi.stubGlobal("Path2D", TestPath);
  vi.stubGlobal("ResizeObserver", class { observe() {} disconnect() {} });
  vi.stubGlobal("requestAnimationFrame", (callback: FrameRequestCallback) => { draw = callback; return 1; });
  vi.stubGlobal("cancelAnimationFrame", vi.fn());
  vi.stubGlobal("matchMedia", () => ({ matches: false }));
  const ctx = {
    filter: "none", globalAlpha: 1,
    setTransform() {}, clearRect() { paths = []; },
    createLinearGradient() { return { addColorStop() {} }; },
    save() {}, restore() { this.filter = "none"; },
    stroke(path: TestPath) { if (this.filter === "none") paths.push(path); },
  };
  vi.spyOn(HTMLCanvasElement.prototype, "getContext").mockReturnValue(ctx as unknown as CanvasRenderingContext2D);
  for (const fixture of reference) {
    const container = document.createElement("div");
    Object.defineProperty(container, "clientWidth", { value: 200 });
    const root = createRoot(container);
    const levelsRef = { current: new Array(90).fill(fixture.level) };
    const bandsRef = { current: fixture.bands };
    await act(async () => root.render(<WaveformVisualizer levelsRef={levelsRef} bandsRef={bandsRef} isActive height={fixture.height} />));
    for (let frame = 0; frame <= fixture.fps; frame++) draw(frame * 1000 / fixture.fps);
    expect(paths).toHaveLength(fixture.paths.length);
    fixture.paths.forEach((expected, strand) => {
      const points = paths[strand].points;
      expected.forEach((y, i) => {
        const fraction = [0, .1, .25, .5, .75, .9, 1][i];
        expect(points[Math.round(fraction * (points.length - 1))][1]).toBeCloseTo(y, 4);
      });
    });
    // Changing the allocated canvas height must preserve phase, even at the same timestamp.
    const before = paths.map(path => path.points.map(([, y]) => (fixture.height / 2 - y) / fixture.height));
    const resizedHeight = fixture.height + 8;
    await act(async () => root.render(<WaveformVisualizer levelsRef={levelsRef} bandsRef={bandsRef} isActive height={resizedHeight} />));
    draw(1000);
    paths.forEach((path, j) => path.points.forEach(([, y], i) => {
      expect((resizedHeight / 2 - y) / resizedHeight).toBeCloseTo(before[j][i], 8);
    }));
    await act(async () => root.unmount());
  }
});
