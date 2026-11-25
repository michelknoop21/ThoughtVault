import { describe, expect, it, vi } from "vitest";
import fixtures from "../../../../../data/mcp/protocol-fixtures.json";
import { handleMessage, TOOLS, type Handler } from "../router";

const never: Handler = vi.fn(async () => { throw new Error("fixtures never reach a handler"); });
const handlers = Object.fromEntries(TOOLS.map(tool => [tool.name, never]));

describe("protocol fixtures shared with macOS", () => {
  type Fixture = { name: string; allowWrite: boolean; request: unknown; expect?: unknown; expectToolNames?: string[]; expectDestructive?: string[] };
  for (const fixture of fixtures.cases as Fixture[]) {
    it(fixture.name, async () => {
      const line = await handleMessage(JSON.stringify(fixture.request), { allowWrite: fixture.allowWrite, version: "1.0.0", handlers });
      if (fixture.expect === null) return expect(line).toBeNull();
      const response = JSON.parse(line!);
      if (fixture.expect) expect(response).toMatchObject(fixture.expect);
      if (fixture.expectToolNames) expect(response.result.tools.map((t: { name: string }) => t.name)).toEqual(fixture.expectToolNames);
      if (fixture.expectDestructive) {
        const destructive = response.result.tools.filter((t: { annotations: { destructiveHint: boolean } }) => t.annotations.destructiveHint === true);
        expect(destructive.map((t: { name: string }) => t.name)).toEqual(fixture.expectDestructive);
        for (const tool of response.result.tools) expect(typeof tool.annotations.destructiveHint).toBe("boolean");
      }
    });
  }
  it("never reached a handler", () => expect(never).not.toHaveBeenCalled());
});

describe("router", () => {
  const ctx = (handler: Handler) => ({ allowWrite: true, version: "1.0.0", handlers: { ...handlers, list_notes: handler } });
  const call = async (handler: Handler, args: unknown = {}) =>
    JSON.parse((await handleMessage(JSON.stringify({ jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: "list_notes", arguments: args } }), ctx(handler)))!);

  it("answers unparseable input with -32700 and id null", async () => {
    expect(JSON.parse((await handleMessage("{nope", ctx(never)))!)).toEqual({ jsonrpc: "2.0", id: null, error: { code: -32700, message: "Parse error" } });
  });

  it("lists tools without scope and with annotations", async () => {
    const response = JSON.parse((await handleMessage(JSON.stringify({ jsonrpc: "2.0", id: 1, method: "tools/list" }), ctx(never)))!);
    const [first, ...rest] = response.result.tools;
    expect(first.scope).toBeUndefined();
    expect(rest.find((t: { name: string }) => t.name === "update_note").destructive).toBeUndefined();
    expect(first.annotations).toEqual({ readOnlyHint: true, destructiveHint: false, openWorldHint: false });
    expect(rest.find((t: { name: string }) => t.name === "update_note").annotations.readOnlyHint).toBe(false);
  });

  it("fills schema defaults and returns structured content", async () => {
    const handler = vi.fn(async (args: Record<string, unknown>) => ({ got: args }));
    const response = await call(handler, { query: "x" });
    expect(handler).toHaveBeenCalledWith({ query: "x", limit: 25, offset: 0 });
    expect(response.result).toEqual({ resultType: "complete", content: [{ type: "text", text: JSON.stringify({ got: { query: "x", limit: 25, offset: 0 } }) }], structuredContent: { got: { query: "x", limit: 25, offset: 0 } } });
  });

  it("turns a handler failure into a tool error", async () => {
    const response = await call(async () => { throw new Error("Notitie niet gevonden."); });
    expect(response.result).toEqual({ resultType: "complete", content: [{ type: "text", text: "Notitie niet gevonden." }], isError: true });
  });

  it("reports schema problems in Dutch", async () => {
    expect((await call(never, { limit: 0 })).result.content[0].text).toBe("Ongeldige invoer: limit moet minstens 1 zijn");
    expect((await call(never, { limit: 2.5 })).result.content[0].text).toMatch(/^Ongeldige invoer: limit moet van type integer/);
  });
});
