import { expect, it, vi } from "vitest";
import { act } from "react";
import { createRoot } from "react-dom/client";
import { useAudioBandsRef } from "../useAudioLevel";
const events = vi.hoisted(() => new Map<string, (event: { payload: number[] }) => void>());
vi.mock("@tauri-apps/api/event", () => ({ listen: vi.fn(async (name, callback) => {
  events.set(name, callback); return () => events.delete(name);
}) }));
it("keeps frequency bands independent, sanitizes values, and unsubscribes", async () => {
  let bands: React.MutableRefObject<number[]>;
  function Meter() { bands = useAudioBandsRef(); return null; }
  const root = createRoot(document.createElement("div"));
  await act(async () => root.render(<Meter />));
  await act(async () => events.get("audio-spectrum")!({ payload: [0, 0.9, 0.2, NaN, -1, 2, Infinity] }));
  expect(bands!.current).toEqual([0, 0.9, 0.2, 0, 0, 1, 0]);
  await act(async () => root.unmount());
  expect(events.has("audio-spectrum")).toBe(false);
});
