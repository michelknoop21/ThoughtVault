import { beforeEach, expect, it, vi } from "vitest";
import { useSettingsStore } from "../../stores/settingsStore";
import { createOffer, loadOfferRef, openOffer } from "../prospectFlow";

const { invoke, loadCredential, open } = vi.hoisted(() => ({ invoke: vi.fn(), loadCredential: vi.fn(), open: vi.fn() }));
vi.mock("@tauri-apps/api/core", () => ({ invoke }));
vi.mock("../tauriCommands", () => ({ loadCredential }));
vi.mock("@tauri-apps/plugin-shell", () => ({ open }));

const input = { taskId: "t1", title: "Gesprek", recordedAt: "2026-11-10T10:00:00Z", notuleHtml: "<p>n</p>", transcript: "tekst" };
const ok = { offer_id: 431, number: "20261110-1", url: "/offers/431/build", klant: { id: 12, naam: "Voorbeeldklant", nieuw: false }, regels: 2, te_controleren: 0, bestaand: false, model: "fixture", terugval_gebruikt: false };
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

it("requires resolving the pending request before another customer gets a new request id", async () => {
  invoke.mockRejectedValueOnce("timeout");
  await expect(createOffer({ ...input, customerId: 12 })).rejects.toThrow();
  const first = loadOfferRef("t1")!.pendingRequestId;
  await expect(createOffer({ ...input, customerId: 13 })).rejects.toThrow("onbevestigde offerteaanvraag");
  expect(invoke).toHaveBeenCalledOnce();
  expect(loadOfferRef("t1")!.pendingRequestId).toBe(first);
  invoke.mockResolvedValueOnce({ status: 201, body: JSON.stringify(ok) });
  await createOffer({ ...input, customerId: 12 });
  expect(body().request_id).toBe(first);
  invoke.mockResolvedValueOnce({ status: 201, body: JSON.stringify({ ...ok, klant: { ...ok.klant, id: 13 } }) });
  await createOffer({ ...input, customerId: 13 });
  expect(body().request_id).not.toBe(first);
});

it("keeps offer links and pending requests within their configured instance", async () => {
  invoke.mockRejectedValueOnce("timeout");
  await expect(createOffer({ ...input, customerId: 12 })).rejects.toThrow();
  const pendingA = loadOfferRef("t1")!.pendingRequestId;
  useSettingsStore.setState({ prospectflow_base_url: "https://other.test" });
  expect(loadOfferRef("t1")).toBeNull();
  invoke.mockResolvedValueOnce({ status: 201, body: JSON.stringify(ok) });
  await createOffer({ ...input, customerId: 12 });
  expect(body().request_id).not.toBe(pendingA);
  useSettingsStore.setState({ prospectflow_base_url: "https://pf.test/" });
  expect(loadOfferRef("t1")!.pendingRequestId).toBe(pendingA);
  expect(loadOfferRef("t1")!.number).toBeUndefined();
});

it("stores the result against the request instance if configuration changes while waiting", async () => {
  invoke.mockImplementationOnce(async () => {
    useSettingsStore.setState({ prospectflow_base_url: "https://other.test" });
    return { status: 201, body: JSON.stringify(ok) };
  });
  const result = await createOffer({ ...input, customerId: 12 });
  expect(loadOfferRef("t1")).toBeNull();
  await openOffer(result.url, result.instanceBaseUrl);
  expect(open).toHaveBeenCalledWith("https://pf.test/offers/431/build");
  useSettingsStore.setState({ prospectflow_base_url: "https://pf.test/" });
  expect(loadOfferRef("t1")!.id).toBe(431);
});

it("captures the opening instance before loading the shell plugin", async () => {
  const opening = openOffer("/offers/3/build");
  useSettingsStore.setState({ prospectflow_base_url: "https://other.test" });
  await opening;
  expect(open).toHaveBeenCalledWith("https://pf.test/offers/3/build");
});

it("does not send an offer when its pending id cannot be saved", async () => {
  const save = vi.spyOn(localStorage, "setItem").mockImplementation(() => {
    throw new DOMException("full", "QuotaExceededError");
  });
  try {
    await expect(createOffer({ ...input, customerId: 12 })).rejects.toThrow();
    expect(invoke).not.toHaveBeenCalled();
  } finally { save.mockRestore(); }
});

it.each(["http://pf.test", "ftp://localhost", "not-a-url"])("rejects unsafe base URL %s before loading a key", async (url) => {
  useSettingsStore.setState({ prospectflow_base_url: url });
  expect(loadOfferRef("t1")).toBeNull();
  await expect(createOffer({ ...input, customerId: 12 })).rejects.toThrow();
  expect(loadCredential).not.toHaveBeenCalled();
  expect(invoke).not.toHaveBeenCalled();
});

it("only reads legacy unscoped references on the original Yinga instance", () => {
  localStorage.setItem("prospectFlowOffer-t1", JSON.stringify({ id: 3, url: "/offers/3/build" }));
  expect(loadOfferRef("t1")).toBeNull();
  useSettingsStore.setState({ prospectflow_base_url: "https://prospectflow.yinga.ai/" });
  expect(loadOfferRef("t1")?.id).toBe(3);
});

it.each(["http://localhost:8089", "http://127.0.0.1:8089", "http://[::1]:8089"])("allows local test URL %s", async (url) => {
  useSettingsStore.setState({ prospectflow_base_url: url });
  invoke.mockResolvedValue({ status: 201, body: JSON.stringify(ok) });
  await createOffer({ ...input, customerId: 12 });
  expect(invoke).toHaveBeenCalledOnce();
});


it.each(["{}", "null", "{", JSON.stringify({ ...ok, klant: null }), JSON.stringify({ ...ok, url: "@other.example.test/path" })])("preserves the pending request after an invalid success reply %s", async reply => {
  invoke.mockResolvedValueOnce({ status: 200, body: reply });
  await expect(createOffer({ ...input, customerId: 12 })).rejects.toThrow();
  const pending = body().request_id;
  expect(loadOfferRef("t1")?.pendingRequestId).toBe(pending);
  invoke.mockResolvedValueOnce({ status: 201, body: JSON.stringify(ok) });
  await createOffer({ ...input, customerId: 12 });
  expect(body().request_id).toBe(pending);
});

it("rejects a redirect response without clearing the pending request", async () => {
  invoke.mockResolvedValueOnce({ status: 307, body: JSON.stringify(ok) });
  await expect(createOffer({ ...input, customerId: 12 })).rejects.toThrow();
  expect(loadOfferRef("t1")?.pendingRequestId).toBe(body().request_id);
});

it.each(["@other.example.test/path", "//other.example.test/path", "https://other.example.test/offers/1", "http://pf.test/offers/1", "javascript:alert(1)"])("never opens an untrusted offer destination %s", async path => {
  await expect(openOffer(path)).rejects.toThrow();
  expect(open).not.toHaveBeenCalled();
});

it("allows replacing a definitively missing customer and preserves the previous completed offer", async () => {
  invoke.mockResolvedValueOnce({ status: 201, body: JSON.stringify(ok) });
  await createOffer({ ...input, customerId: 12 });
  const completed = loadOfferRef("t1");
  invoke.mockResolvedValueOnce({ status: 404, body: JSON.stringify({ detail: "Klant niet gevonden" }) });
  await expect(createOffer({ ...input, customerId: 99 })).rejects.toThrow("Klant niet gevonden");
  expect(loadOfferRef("t1")).toEqual(completed);
  invoke.mockResolvedValueOnce({ status: 201, body: JSON.stringify({ ...ok, klant: { ...ok.klant, id: 13 } }) });
  await createOffer({ ...input, customerId: 13 });
  expect(body().customer_id).toBe(13);
});

it.each([
  { status: 404, body: "<html>Klant niet gevonden</html>" },
  { status: 404, body: JSON.stringify({ detail: "Pagina niet gevonden" }) },
  { status: 404, body: '{"detail":"Klant niet gevonden"' },
  { status: 409, body: JSON.stringify({ detail: "Klant niet gevonden" }) },
  { status: 503, body: JSON.stringify({ detail: "Klant niet gevonden" }) },
])("keeps pending identity for an unconfirmed error $status $body", async response => {
  invoke.mockResolvedValueOnce(response);
  await expect(createOffer({ ...input, customerId: 12 })).rejects.toThrow();
  const pending = loadOfferRef("t1");
  expect(pending?.pendingRequestId).toBeTruthy();
  await expect(createOffer({ ...input, customerId: 13 })).rejects.toThrow("onbevestigde offerteaanvraag");
  expect(loadOfferRef("t1")).toEqual(pending);
  expect(invoke).toHaveBeenCalledOnce();
});

it("sends the colleague's e-mail so the draft lands in their own inbox", async () => {
  const { useSupportStore } = await import("../../stores/supportStore");
  invoke.mockResolvedValue({ status: 201, body: JSON.stringify(ok) });
  useSupportStore.setState({ email: "collega@example.com" });
  await createOffer({ ...input, customerId: 12 });
  expect(body().maker_email).toBe("collega@example.com");
  useSupportStore.setState({ email: "" });
  await createOffer({ ...input, taskId: "t3", customerId: 12 });
  expect(body()).not.toHaveProperty("maker_email");
});
