import { beforeEach, expect, it, vi } from "vitest";
import { SSEClient } from "../sse";

const mocks = vi.hoisted(() => ({ listeners: new Map<string, (event: { payload: string }) => void>() }));
vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn(async () => {}) }));
vi.mock("@tauri-apps/api/event", () => ({ listen: vi.fn(async (name, callback) => {
  mocks.listeners.set(name, callback);
  return () => { mocks.listeners.delete(name); };
}) }));
beforeEach(() => mocks.listeners.clear());

it.each(["completed", "failed", "cancelled", "error"])("passes terminal %s to the caller after preserving the update", async (status) => {
  const update = vi.fn();
  const complete = vi.fn();
  const client = new SSEClient("https://qa.invalid/task", null);
  await client.connect(update, undefined, complete);
  const listener = [...mocks.listeners.values()][0];
  listener({ payload: JSON.stringify({ task_id: "qa", status, error_message: "Eigen QA-fout" }) });
  expect(update).toHaveBeenCalledWith(expect.objectContaining({ status, error_message: "Eigen QA-fout" }));
  expect(complete).toHaveBeenCalledExactlyOnceWith(status);
  expect(mocks.listeners.size).toBe(0);
});
it("still completes a legacy DONE stream without a status", async () => {
  const complete = vi.fn();
  const client = new SSEClient("https://qa.invalid/task", null);
  await client.connect(vi.fn(), undefined, complete);
  const done = [...mocks.listeners.entries()].find(([name]) => name.endsWith("-done"))![1];
  done({ payload: "" });
  expect(complete).toHaveBeenCalledOnce();
  expect(mocks.listeners.size).toBe(0);
});
