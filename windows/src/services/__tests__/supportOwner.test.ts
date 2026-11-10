import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { startSupportOwner, requireSupportOwner } from "../supportOwner";
import { WIDGET_ACK_EVENT, WIDGET_FAILURE_EVENT } from "../widgetSupport";

const fake = vi.hoisted(() => ({
  receive: undefined as undefined | ((event: { payload: unknown }) => void),
  enqueue: vi.fn(), durable: vi.fn(), flush: vi.fn(), emit: vi.fn(), stop: vi.fn(),
}));
vi.mock("@tauri-apps/api/window", () => ({ getCurrentWindow: () => ({ label: "main" }) }));
vi.mock("@tauri-apps/api/event", () => ({
  emitTo: fake.emit,
  listen: vi.fn(async (name, callback) => {
    if (name === WIDGET_FAILURE_EVENT) fake.receive = callback;
    return fake.stop;
  }),
}));
vi.mock("../crashReporter", () => ({ enqueueFailure: fake.enqueue }));
vi.mock("../../stores/supportStore", () => ({
  isSupportReportDurable: fake.durable,
  useSupportStore: { getState: () => ({ flushQueue: fake.flush }) },
}));
let stop: (() => void) | undefined;
const failure = { id: "11111111-1111-4111-8111-111111111111", code: "pause_failed" };
async function drain() { for (let n = 0; n < 10; n++) await Promise.resolve(); }
beforeEach(() => {
  vi.clearAllMocks(); fake.enqueue.mockResolvedValue("queued");
  fake.durable.mockReturnValue(false); fake.flush.mockResolvedValue(undefined); fake.emit.mockResolvedValue(undefined);
});
afterEach(() => { stop?.(); stop = undefined; });
async function start() { stop = startSupportOwner(); await requireSupportOwner(); }
it("ACKs after enqueue, retaining ID after flush and a lost first ACK", async () => {
  await start();
  fake.emit.mockRejectedValueOnce(new Error("lost ACK"));
  fake.receive!({ payload: failure }); await drain();
  fake.receive!({ payload: failure }); await drain();
  expect(fake.enqueue).toHaveBeenCalledTimes(1);
  expect(fake.enqueue).toHaveBeenCalledWith("opnemen", "Pauzeren mislukt", "widget_pause_failed", failure.id);
  expect(fake.emit).toHaveBeenLastCalledWith("recording-widget", WIDGET_ACK_EVENT, { id: failure.id, outcome: "queued" });
  expect(fake.enqueue.mock.invocationCallOrder[0]).toBeLessThan(fake.emit.mock.invocationCallOrder[0]);
});
it("does not ACK failed storage or flush an opt-out discard", async () => {
  await start(); fake.enqueue.mockResolvedValueOnce("failed");
  fake.receive!({ payload: failure }); await drain();
  expect(fake.emit).not.toHaveBeenCalled();
  fake.enqueue.mockResolvedValueOnce("discarded");
  fake.receive!({ payload: failure }); await drain();
  expect(fake.emit).toHaveBeenCalledWith("recording-widget", WIDGET_ACK_EVENT, { id: failure.id, outcome: "discarded" });
  expect(fake.flush).not.toHaveBeenCalled();
});
it("rejects unapproved metadata and removes its listener on teardown", async () => {
  await start();
  fake.receive!({ payload: { ...failure, code: "stop_failed", error: "private" } }); await drain();
  expect(fake.enqueue).not.toHaveBeenCalled();
  stop!(); stop = undefined;
  expect(fake.stop).toHaveBeenCalledTimes(1);
  await expect(requireSupportOwner()).rejects.toThrow("not ready");
});
it("leaves a durable enqueue recoverable when its owner is disposed during preparation", async () => {
  await start();
  let finish!: (outcome: string) => void;
  fake.enqueue.mockReturnValueOnce(new Promise(resolve => { finish = resolve; }));
  fake.receive!({ payload: failure }); await drain();
  stop!(); stop = undefined;
  fake.durable.mockReturnValue(true);
  finish("queued"); await drain();
  expect(fake.emit).not.toHaveBeenCalled();
  expect(fake.flush).not.toHaveBeenCalled();
  await start(); fake.receive!({ payload: failure }); await drain();
  expect(fake.enqueue).toHaveBeenCalledTimes(1);
  expect(fake.emit).toHaveBeenCalledWith("recording-widget", WIDGET_ACK_EVENT, { id: failure.id, outcome: "queued" });
});
