import { beforeEach, describe, expect, it, vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";
import { listTickets, postMessage, registerInstallation, sendReport, ticketMessages, unreadCount, type ReportPayload } from "../supportRelay";
vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn() }));
const inst = { id: "6f1c0d7e-0000-4000-8000-000000000001", secret: "a".repeat(43) };
const payload: ReportPayload = { kind: "auto", category: "BUG", stage: "crash", shownMessage: "De app is gestopt.", errorText: "failure", fingerprint: "abcdef0123456789", clickPath: ["Instellingen"], appVersion: "1.0.312", os: "Windows 11", device: "PC", platform: "windows", name: "Example", email: "test@example.com", occurredAt: "2026-11-10T10:00:00.123Z", log: "example log" };
const result = { ticketId: "t1", ref: "TV-000001", repeated: false, count: 1, logAttached: true };
const ticket = { id: "a", ref: "TV-000002", status: "WAITING_FOR_USER", category: "BUG", description: "d", createdAt: "2026-11-10T10:00:00.123Z", unread: true };
const message = { id: "m", body: "Opgelost", senderRole: "admin", createdAt: "2026-11-10T11:00:00.123Z" };
const reply = (status: number, body: unknown, headers: Record<string, string> = {}) => vi.mocked(invoke).mockResolvedValueOnce({ status, body: JSON.stringify(body), headers });
beforeEach(() => vi.mocked(invoke).mockReset());
describe("support relay transport", () => {
  it("posts reports through proxy_request with only installation headers", async () => {
    reply(200, result); expect(await sendReport(inst, payload)).toEqual(result);
    expect(invoke).toHaveBeenCalledExactlyOnceWith("proxy_request", { request: { url: "https://thoughtvault.yinga.ai/support/reports", method: "POST", timeout_seconds: 60, headers: { "Content-Type": "application/json", "X-TV-Installation": inst.id, "X-TV-Secret": inst.secret }, body: JSON.stringify(payload) } });
  });
  it("registers without installation headers and maps 201, 200 and 409", async () => {
    reply(201, {}); reply(200, {}); reply(409, {});
    expect(await registerInstallation(inst.id, inst.secret)).toBe("created"); expect(await registerInstallation(inst.id, inst.secret)).toBe("exists"); expect(await registerInstallation(inst.id, inst.secret)).toBe("conflict");
    expect(invoke).toHaveBeenNthCalledWith(1, "proxy_request", { request: { url: "https://thoughtvault.yinga.ai/support/installations", method: "POST", timeout_seconds: 60, headers: { "Content-Type": "application/json" }, body: JSON.stringify({ installationId: inst.id, secret: inst.secret }) } });
  });
  it("treats logAttached false as successful delivery", async () => {
    reply(200, { ...result, logAttached: false }); expect(await sendReport(inst, payload)).toEqual({ ...result, logAttached: false }); expect(invoke).toHaveBeenCalledTimes(1);
  });
  it("reads data envelopes, millisecond dates and absent updatedAt and posts unwrapped messages", async () => {
    reply(200, { data: [ticket], pagination: {} }); reply(200, { data: { count: 3 } }); reply(200, { data: [message] }); reply(201, message);
    expect(await listTickets(inst)).toEqual([ticket]); expect(await unreadCount(inst)).toBe(3); expect(await ticketMessages(inst, "a")).toEqual([message]); expect(await postMessage(inst, "a", "Bedankt")).toEqual(message);
    expect(invoke).toHaveBeenNthCalledWith(3, "proxy_request", { request: expect.objectContaining({ url: "https://thoughtvault.yinga.ai/support/tickets/a/messages", method: "GET", body: null }) });
    expect(invoke).toHaveBeenNthCalledWith(4, "proxy_request", { request: expect.objectContaining({ method: "POST", body: JSON.stringify({ body: "Bedankt" }) }) });
  });
  it("preserves optional updatedAt and lastMessage", async () => {
    const updated = { ...ticket, updatedAt: "2026-11-10T12:00:00.123Z", lastMessage: { senderRole: "ADMIN", createdAt: "2026-11-10T12:00:00.123Z", excerpt: "Antwoord" } }; reply(200, { data: [updated] }); expect(await listTickets(inst)).toEqual([updated]);
  });
  it("accepts null lastMessage but rejects obsolete string summaries", async () => {
    reply(200, { data: [{ ...ticket, lastMessage: null }] }); expect(await listTickets(inst)).toEqual([{ ...ticket, lastMessage: null }]);
    reply(200, { data: [{ ...ticket, lastMessage: "old string" }] }); await expect(listTickets(inst)).rejects.toMatchObject({ status: 502 });
  });
  it.each([401, 409, 413, 422, 429, 502, 503])("preserves HTTP %i without transport retries", async (status) => {
    reply(status, { detail: { error_code: "example_error", message: "Voorbeeldfout" } }); await expect(sendReport(inst, payload)).rejects.toMatchObject({ status, message: "Voorbeeldfout", errorCode: "example_error" }); expect(invoke).toHaveBeenCalledTimes(1);
  });
  it.each(["retry-after", "Retry-After"])("exposes %s seconds to the queue", async (key) => {
    reply(429, {}, { [key]: "75", "set-cookie": "private" }); await expect(listTickets(inst)).rejects.toMatchObject({ status: 429, retryAfterSeconds: 75 });
  });
  it.each(["bad", "-1", "1.5", "Infinity", "9007199254740992"])("ignores invalid Retry-After %s", async (value) => {
    reply(429, {}, { "retry-after": value }); await expect(listTickets(inst)).rejects.toMatchObject({ retryAfterSeconds: undefined });
  });
  it("does not expose raw network errors, bodies or validation inputs and bounds messages", async () => {
    vi.mocked(invoke).mockRejectedValueOnce(`secret=${inst.secret}`); await expect(listTickets(inst)).rejects.toMatchObject({ status: 0, message: "Kan de supportserver niet bereiken." });
    vi.mocked(invoke).mockResolvedValueOnce({ status: 502, body: `private ${inst.secret}`, headers: {} }); await expect(listTickets(inst)).rejects.toMatchObject({ status: 502, message: "Supportverzoek mislukt (HTTP 502)." });
    reply(422, { detail: [{ input: inst.secret }] }); await expect(listTickets(inst)).rejects.toMatchObject({ message: "Supportverzoek mislukt (HTTP 422)." });
    reply(503, { detail: { message: "x".repeat(1000) } }); await expect(listTickets(inst)).rejects.toMatchObject({ message: "x".repeat(500) });
  });
  it.each([[], { tickets: [] }, { data: [null] }, { data: [{ ...ticket, unread: "yes" }] }])("rejects malformed ticket envelopes", async (body) => { reply(200, body); await expect(listTickets(inst)).rejects.toMatchObject({ status: 502 }); });
  it.each([{ count: 3 }, { data: { count: -1 } }, { data: { count: "3" } }])("rejects malformed unread envelopes", async (body) => { reply(200, body); await expect(unreadCount(inst)).rejects.toMatchObject({ status: 502 }); });
  it.each([200, 201])("keeps HTTP %i report acceptance when the receipt is malformed", async status => {
    reply(status, { ...result, logAttached: undefined }); expect(await sendReport(inst, payload)).toBeNull();
    vi.mocked(invoke).mockResolvedValueOnce({ status, body: "<html>", headers: {} });
    expect(await sendReport(inst, payload)).toBeNull(); expect(invoke).toHaveBeenCalledTimes(2);
  });
  it("rejects malformed message replies and JSON", async () => {
    reply(200, [message]); await expect(ticketMessages(inst, "a")).rejects.toMatchObject({ status: 502 });
    reply(201, { data: message }); await expect(postMessage(inst, "a", "test")).rejects.toMatchObject({ status: 502 });
    vi.mocked(invoke).mockResolvedValueOnce({ status: 200, body: "<html>", headers: {} }); await expect(listTickets(inst)).rejects.toMatchObject({ status: 502 });
  });
  it.each(["../other", "a/b", "a?key=x", "", "x".repeat(65)])("rejects unsafe ticket id %s before invoking", async (id) => {
    await expect(ticketMessages(inst, id)).rejects.toMatchObject({ status: 422 }); await expect(postMessage(inst, id, "hello")).rejects.toMatchObject({ status: 422 }); expect(invoke).not.toHaveBeenCalled();
  });
  it.each(["", "x".repeat(5001)])("rejects invalid message length", async (body) => { await expect(postMessage(inst, "a", body)).rejects.toMatchObject({ status: 422 }); expect(invoke).not.toHaveBeenCalled(); });
  it.each([{ shownMessage: "" }, { shownMessage: "x".repeat(5001) }, { errorText: "x".repeat(2001) }, { clickPath: Array(31).fill("x") }, { clickPath: ["x".repeat(81)] }, { appVersion: "x".repeat(101) }, { name: "x".repeat(201) }, { email: "x".repeat(321) }, { occurredAt: "x".repeat(41) }, { log: "é".repeat(500001) }, { category: "QUESTION" }, { stage: "" }, { fingerprint: "G".repeat(16) }])("rejects invalid report input", async (changes) => {
    await expect(sendReport(inst, { ...payload, ...changes } as ReportPayload)).rejects.toMatchObject({ status: 422 }); expect(invoke).not.toHaveBeenCalled();
  });
  it("accepts manual reports and boundary limits", async () => {
    const manual: ReportPayload = { ...payload, kind: "manual", category: "QUESTION", stage: "", fingerprint: undefined, shownMessage: "x".repeat(5000), errorText: "x".repeat(2000), clickPath: Array(30).fill("x".repeat(80)), log: "é".repeat(500000) }; reply(200, result); expect(await sendReport(inst, manual)).toEqual(result);
  });
  it("rejects invalid credentials before invoking", async () => {
    await expect(registerInstallation("bad", inst.secret)).rejects.toMatchObject({ status: 422 }); await expect(listTickets({ ...inst, secret: "bad\r\nheader" })).rejects.toMatchObject({ status: 422 }); expect(invoke).not.toHaveBeenCalled();
  });
});
