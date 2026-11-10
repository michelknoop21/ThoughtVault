import { beforeEach, expect, it, vi } from "vitest";
import { useSettingsStore } from "../../stores/settingsStore";
import { createOffer, loadOfferRef } from "../prospectFlow";

const { invoke, loadCredential } = vi.hoisted(() => ({ invoke: vi.fn(), loadCredential: vi.fn() }));
vi.mock("@tauri-apps/api/core", () => ({ invoke }));
vi.mock("../tauriCommands", () => ({ loadCredential }));

const input = { taskId: "t1", title: "Gesprek", recordedAt: "2026-11-10T10:00:00Z", notuleHtml: "<p>n</p>", transcript: "tekst" };
const ok = { offer_id: 431, number: "20261110-1", url: "/offers/431/build" };
const body = () => JSON.parse(invoke.mock.calls.at(-1)![1].request.body);

beforeEach(() => {
  vi.resetAllMocks();
  localStorage.clear();
  useSettingsStore.setState({ prospectflow_base_url: "https://pf.test/" });
  loadCredential.mockResolvedValue("sleutel");
});

it("sends exactly one of customer_id / new_customer_name and the API key", async () => {
  invoke.mockResolvedValue({ status: 201, body: JSON.stringify(ok) });
  await createOffer({ ...input, customerId: 12 });
  expect(invoke.mock.calls[0][1].request).toMatchObject({ url: "https://pf.test/api/ai/offers/from-conversation", headers: { "X-API-Key": "sleutel" }, timeout_seconds: 300 });
  expect(body()).toMatchObject({ customer_id: 12, transcript_id: "t1" });
  expect(body()).not.toHaveProperty("new_customer_name");
  await createOffer({ ...input, taskId: "t2", newCustomerName: "Nieuw BV" });
  expect(body().new_customer_name).toBe("Nieuw BV");
  expect(body()).not.toHaveProperty("customer_id");
  await expect(createOffer({ ...input, customerId: 1, newCustomerName: "x" })).rejects.toThrow();
});

it("reuses pendingRequestId after a failure and clears it on success", async () => {
  invoke.mockRejectedValueOnce("timeout");
  await expect(createOffer({ ...input, customerId: 12 })).rejects.toThrow("niet bereikbaar");
  const pending = loadOfferRef("t1")!.pendingRequestId;
  expect(pending).toBeTruthy();
  invoke.mockResolvedValueOnce({ status: 201, body: JSON.stringify(ok) });
  await createOffer({ ...input, customerId: 12 });
  expect(body().request_id).toBe(pending);
  expect(loadOfferRef("t1")).toEqual({ id: 431, number: "20261110-1", url: "/offers/431/build" });
});

it("shows the server detail, or a Dutch fallback by status", async () => {
  invoke.mockResolvedValueOnce({ status: 403, body: JSON.stringify({ detail: "AI-hulpen staan uit." }) });
  await expect(createOffer({ ...input, customerId: 1 })).rejects.toThrow("AI-hulpen staan uit.");
  invoke.mockResolvedValueOnce({ status: 503, body: "" });
  await expect(createOffer({ ...input, customerId: 1 })).rejects.toThrow("niet bereikbaar");
});

it("gives another customer choice a new request id", async () => {
  invoke.mockRejectedValueOnce("timeout");
  await expect(createOffer({ ...input, customerId: 12 })).rejects.toThrow();
  const first = loadOfferRef("t1")!.pendingRequestId;
  invoke.mockRejectedValueOnce("timeout");
  await expect(createOffer({ ...input, customerId: 13 })).rejects.toThrow();
  expect(loadOfferRef("t1")!.pendingRequestId).not.toBe(first);
});
