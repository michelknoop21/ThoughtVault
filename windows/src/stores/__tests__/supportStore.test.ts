import { beforeEach, afterEach, expect, it, vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";
vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn() }));
let support: typeof import("../supportStore");
const creds = new Map<string, string>();
const answers: Record<string, Array<number | "offline" | "malformed">> = {};
const sent: Array<{ path: string; body: any; headers: Record<string, string> }> = [];
let pause: (() => Promise<void>) | undefined;
const item = (over: Partial<import("../supportStore").QueuedReport> = {}): import("../supportStore").QueuedReport => ({
  id: crypto.randomUUID(), kind: "auto", category: "BUG", stage: "notule", shownMessage: "Notule maken mislukt",
  errorText: "Provider niet bereikbaar", fingerprint: "390655eba19539fc", clickPath: ["knop: Opnemen"],
  occurredAt: "2026-11-10T10:00:00.000Z", ...over,
});
const state = () => support.useSupportStore.getState();
const reports = () => sent.filter(s => s.path === "/reports");
beforeEach(async () => {
  vi.resetModules(); vi.useFakeTimers(); localStorage.clear(); creds.clear(); sent.length = 0; pause = undefined;
  for (const key of Object.keys(answers)) delete answers[key];
  vi.mocked(invoke).mockImplementation(async (cmd, args: any) => {
    if (cmd === "store_credential") { creds.set(args.key, args.value); return; }
    if (cmd === "load_credential") return creds.get(args.key) ?? null;
    if (cmd === "log_tail") return "log-tail";
    if (cmd === "get_app_version") return "1.0.312";
    if (cmd === "get_system_specs") return { cpu: "Review CPU", memory_gb: 16, os_version: "Windows 11" };
    if (cmd === "proxy_request") {
      const path = args.request.url.replace("https://thoughtvault.yinga.ai/support", "");
      sent.push({ path, body: args.request.body ? JSON.parse(args.request.body) : null, headers: args.request.headers });
      if (path === "/reports" && pause) await pause();
      const status = answers[path]?.shift() ?? (path === "/installations" ? 201 : 200);
      if (status === "offline") throw new Error("offline");
      return { status: status === "malformed" ? 200 : status, headers: status === 429 || status === 503 ? { "Retry-After": "60" } : {}, body: status === "malformed" ? "not JSON" : JSON.stringify(path === "/unread-count" ? { data: { count: 3 } } : { ticketId: "t", ref: "TV-1", repeated: false, count: 1, logAttached: false }) };
    }
  });
  support = await import("../supportStore");
  support.useSupportStore.setState({ name: "Jan", email: "jan@example.com" });
});
afterEach(() => { vi.restoreAllMocks(); vi.useRealTimers(); });
it("registers once and sends identity, versions and a fresh log without persisting secrets or logs", async () => {
  state().enqueue(item());
  expect(localStorage.getItem("support-store")).not.toContain("log-tail");
  await state().flushQueue();
  expect(sent.filter(s => s.path === "/installations")).toHaveLength(1);
  expect(reports()[0].body).toMatchObject({ platform: "windows", name: "Jan", email: "jan@example.com", appVersion: "1.0.312", os: "Windows 11", log: "log-tail" });
  const secret = creds.get("support_secret")!;
  expect(secret).toMatch(/^[A-Za-z0-9_-]{43}$/);
  expect(localStorage.getItem("support-store")).not.toContain(secret);
  expect(state().queue).toHaveLength(0);
});
it("sends a queued report once when two flushes overlap after reconnect", async () => {
  answers["/reports"] = ["offline"]; state().enqueue(item()); await state().flushQueue();
  await Promise.all([state().flushQueue(), state().flushQueue()]);
  expect(reports()).toHaveLength(2); expect(state().queue).toHaveLength(0);
});
it("waits for name and e-mail before sending", async () => {
  support.useSupportStore.setState({ name: "", email: "bad" }); state().enqueue(item()); await state().flushQueue();
  expect(reports()).toHaveLength(0); expect(state().queue).toHaveLength(1);
  state().setIdentity(" Jan ", " jan@example.com "); await state().flushQueue();
  expect(state().name).toBe("Jan"); expect(state().email).toBe("jan@example.com"); expect(state().queue).toHaveLength(0);
});
it("re-registers after 401 and moves to a new installation after 409", async () => {
  state().enqueue(item()); await state().flushQueue(); sent.length = 0;
  const oldId = state().installation_id; const oldSecret = creds.get("support_secret");
  answers["/reports"] = [401, 200]; answers["/installations"] = [409, 201];
  state().enqueue(item()); await state().flushQueue();
  expect(reports()).toHaveLength(2); expect(sent.filter(s => s.path === "/installations")).toHaveLength(2);
  expect(state().installation_id).not.toBe(oldId); expect(creds.get("support_secret")).not.toBe(oldSecret);
});
it("stops after one request retry on a second 401", async () => {
  answers["/reports"] = [401, 401]; state().enqueue(item()); await state().flushQueue();
  expect(reports()).toHaveLength(2); expect(sent.filter(s => s.path === "/installations")).toHaveLength(2);
});
it("shares registration across concurrent callers", async () => {
  await Promise.all([support.withInstallation(async i => i.id), state().refreshUnread(), state().refreshUnread()]);
  expect(sent.filter(s => s.path === "/installations")).toHaveLength(1);
});
it.each(["/installations", "/reports", "/unread-count"])("honors Retry-After from %s across all calls", async path => {
  answers[path] = [429]; state().enqueue(item());
  if (path === "/unread-count") await state().refreshUnread(); else await state().flushQueue();
  const count = sent.length;
  await state().refreshUnread(); await state().flushQueue();
  await expect(support.withInstallation(async () => 1)).rejects.toMatchObject({ status: 429 });
  expect(sent).toHaveLength(count); expect(state().queue).toHaveLength(1);
  vi.advanceTimersByTime(60_001); await state().flushQueue(); expect(state().queue).toHaveLength(0);
});
it("retries a 413 once without the log", async () => {
  answers["/reports"] = [413, 200]; state().enqueue(item()); await state().flushQueue();
  expect(reports()[1].body.log).toBe(""); expect(state().queue).toHaveLength(0);
});
it.each(["offline", 429, 503] as const)("keeps a 413 retry on transient %s", async status => {
  answers["/reports"] = [413, status]; state().enqueue(item()); await state().flushQueue();
  expect(state().queue).toHaveLength(1);
});
it("drops queued auto reports when switched off and still sends manual reports", async () => {
  state().enqueue(item()); state().setAutoReport(false);
  expect(state().queue).toHaveLength(0); state().enqueue(item()); expect(state().queue).toHaveLength(0);
  expect(await state().submitManual("QUESTION", "Hoe exporteer ik?")).toBe("sent");
  expect(reports().map(r => r.body.kind)).toEqual(["manual"]);
});
it("returns queued only for a durable offline manual report", async () => {
  answers["/reports"] = ["offline"];
  expect(await state().submitManual("QUESTION", "Hoe exporteer ik?")).toBe("queued");
  expect(state().queue[0]).toMatchObject({ kind: "manual", stage: "", errorText: "" });
});
it.each([400, 413])("returns failed for a permanently rejected manual report (%s)", async status => {
  answers["/reports"] = [status, status];
  expect(await state().submitManual("QUESTION", "Vraag")).toBe("failed"); expect(state().queue).toHaveLength(0);
});
it("does not send or claim queued if storage cannot retain a new manual report", async () => {
  vi.spyOn(localStorage, "setItem").mockImplementation(() => { throw new Error("disk full"); });
  expect(await state().submitManual("QUESTION", "Vraag")).toBe("failed"); expect(reports()).toHaveLength(0);
});
it("never reposts after ACK when queue cleanup storage fails", async () => {
  let fail = true;
  pause = async () => { if (fail) vi.spyOn(localStorage, "setItem").mockImplementation(() => { throw new Error("disk full"); }); };
  expect(await state().submitManual("QUESTION", "Vraag")).toBe("sent");
  await state().flushQueue(); expect(reports()).toHaveLength(1);
  fail = false; vi.restoreAllMocks(); await state().flushQueue(); expect(reports()).toHaveLength(1);
  expect(JSON.parse(localStorage.getItem("support-store")!).state.queue).toHaveLength(0);
});
it("treats malformed success receipts as accepted without a duplicate POST", async () => {
  answers["/reports"] = ["malformed"];
  expect(await state().submitManual("QUESTION", "Vraag")).toBe("sent"); await state().flushQueue();
  expect(reports()).toHaveLength(1);
});
it("preserves newly enqueued items during an active flush and caps at 50", async () => {
  let release!: () => void; const held = new Promise<void>(r => { release = r; });
  let started!: () => void; const ready = new Promise<void>(r => { started = r; });
  pause = async () => { started(); await held; };
  const first = item(); state().enqueue(first); const flushing = state().flushQueue(); await ready;
  for (let n = 0; n < 55; n++) state().enqueue(item({ shownMessage: `item ${n}` }));
  expect(state().queue).toHaveLength(50); expect(state().queue[0].id).toBe(first.id);
  pause = undefined; release(); await flushing;
  expect(reports()).toHaveLength(50); expect(reports().at(-1)?.body.shownMessage).toBe("item 54");
});
it("validates trimmed e-mail addresses", () => {
  expect(support.isValidEmail(" jan@example.com ")).toBe(true);
  expect(["", "jan@", "jan example.com", "jan@example"].some(support.isValidEmail)).toBe(false);
});

it("restores a missing credential through conflict recovery without storing it in metadata", async () => {
  support.useSupportStore.setState({ installation_id: crypto.randomUUID() });
  answers["/installations"] = [409, 201];
  state().enqueue(item()); await state().flushQueue();
  expect(sent.filter(s => s.path === "/installations")).toHaveLength(2);
  expect(reports()).toHaveLength(1); expect(state().queue).toHaveLength(0);
});
it("registers the same pair before retrying an unauthorized request", async () => {
  answers["/reports"] = [401, 200]; state().enqueue(item()); await state().flushQueue();
  const registrations = sent.filter(s => s.path === "/installations");
  expect(registrations).toHaveLength(2); expect(registrations[0].body).toEqual(registrations[1].body);
  expect(reports()).toHaveLength(2);
});
it("retains all reports after 429 and ignores untyped log and secret fields", async () => {
  answers["/reports"] = [429];
  state().enqueue({ ...item(), log: "private-log", secret: "private-secret" } as any); state().enqueue(item());
  await state().flushQueue(); expect(reports()).toHaveLength(1); expect(state().queue).toHaveLength(2);
  expect(localStorage.getItem("support-store")).not.toContain("private-log");
  expect(localStorage.getItem("support-store")).not.toContain("private-secret");
});
it("reads the current log at send time", async () => {
  state().enqueue(item());
  const original = vi.mocked(invoke).getMockImplementation()!;
  vi.mocked(invoke).mockImplementation((cmd, args) => cmd === "log_tail" ? Promise.resolve("fresh-log") : original(cmd, args));
  await state().flushQueue(); expect(reports()[0].body.log).toBe("fresh-log");
});

it("shares a single recovery registration across simultaneous 401 responses", async () => {
  const { RelayError } = await import("../../services/supportRelay");
  const request = () => {
    let attempts = 0;
    return support.withInstallation(async () => { if (++attempts === 1) throw new RelayError(401, "Unauthorized"); return attempts; });
  };
  expect(await Promise.all([request(), request()])).toEqual([2, 2]);
  expect(sent.filter(s => s.path === "/installations")).toHaveLength(2);
});
it.each(["initial", "401", "413"])("checks automatic consent again after %s installation waits", async phase => {
  let release!: () => void; const held = new Promise<void>(r => { release = r; });
  let started!: () => void; const ready = new Promise<void>(r => { started = r; });
  const original = vi.mocked(invoke).getMockImplementation()!;
  let reads = 0;
  vi.mocked(invoke).mockImplementation(async (cmd, args) => {
    if (cmd === "load_credential" && ++reads === (phase === "initial" ? 1 : 2)) { started(); await held; }
    return original(cmd, args);
  });
  if (phase !== "initial") answers["/reports"] = [Number(phase), 200];
  state().enqueue(item()); const running = state().flushQueue(); await ready;
  state().setAutoReport(false); release(); await running;
  expect(reports()).toHaveLength(phase === "initial" ? 0 : 1);
  expect(state().queue).toHaveLength(0);
});
it("holds a manual report when identity becomes incomplete during registration", async () => {
  let release!: () => void; const held = new Promise<void>(r => { release = r; });
  let started!: () => void; const ready = new Promise<void>(r => { started = r; });
  const original = vi.mocked(invoke).getMockImplementation()!;
  vi.mocked(invoke).mockImplementation(async (cmd, args) => {
    if (cmd === "load_credential") { started(); await held; }
    return original(cmd, args);
  });
  const sending = state().submitManual("QUESTION", "Vraag"); await ready;
  support.useSupportStore.setState({ name: "", email: "" }); release();
  expect(await sending).toBe("queued"); expect(reports()).toHaveLength(0);
  expect(state().queue).toHaveLength(1);
});
it("sends the current identity after registration waits", async () => {
  const original = vi.mocked(invoke).getMockImplementation()!;
  vi.mocked(invoke).mockImplementation(async (cmd, args) => {
    if (cmd === "load_credential") state().setIdentity("Alex", "alex@example.com");
    return original(cmd, args);
  });
  expect(await state().submitManual("QUESTION", "Vraag")).toBe("sent");
  expect(reports()[0].body).toMatchObject({ name: "Alex", email: "alex@example.com" });
});

it("validates relay contact boundaries in code points without truncating", () => {
  const email = "a".repeat(314) + "@b.com";
  expect(support.isCompleteIdentity(" n ", " " + email + " ")).toBe(true);
  expect(support.isCompleteIdentity("n".repeat(200), email)).toBe(true);
  expect(support.isCompleteIdentity("n".repeat(201), email)).toBe(false);
  expect(support.isCompleteIdentity("n", "a" + email)).toBe(false);
  expect(support.isCompleteIdentity("😀".repeat(200), email)).toBe(true);
  state().setIdentity("n".repeat(201), email);
  expect(state().name).toBe("Jan");
});
it.each(["name", "email"])("holds reports for previously stored overlong %s until corrected", async field => {
  support.useSupportStore.setState({ [field]: field === "name" ? "n".repeat(201) : "a".repeat(315) + "@b.com" });
  state().enqueue(item()); await state().flushQueue();
  expect(reports()).toHaveLength(0); expect(state().queue).toHaveLength(1);
  state().setIdentity("Jan", "jan@example.com"); await state().flushQueue();
  expect(reports()).toHaveLength(1); expect(state().queue).toHaveLength(0);
});
it("holds a manual report if stored identity overflows during registration", async () => {
  const original = vi.mocked(invoke).getMockImplementation()!;
  vi.mocked(invoke).mockImplementation(async (cmd, args) => {
    if (cmd === "load_credential") support.useSupportStore.setState({ name: "n".repeat(201) });
    return original(cmd, args);
  });
  expect(await state().submitManual("QUESTION", "Draft retained")).toBe("queued");
  expect(reports()).toHaveLength(0); expect(state().queue[0].shownMessage).toBe("Draft retained");
});
