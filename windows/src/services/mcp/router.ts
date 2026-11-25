// JSON-RPC router of the local MCP server. Pure: the socket and the app data stay outside.
// Behaviour is shared with macOS through data/mcp/tools.json and protocol-fixtures.json.
import contract from "../../../../data/mcp/tools.json";

export const SUPPORTED_VERSIONS = ["2026-07-28", "2025-11-25", "2025-06-18", "2025-03-26"];
const FALLBACK_VERSION = "2025-11-25";
const SERVER_NAME = "ThoughtVault";

export type Handler = (args: Record<string, unknown>) => Promise<unknown>;
export interface RouterContext {
  allowWrite: boolean;
  version: string;
  handlers: Record<string, Handler>;
}

export interface Schema {
  type?: string | string[];
  properties?: Record<string, Schema>;
  required?: string[];
  additionalProperties?: boolean;
  enum?: unknown[];
  minLength?: number;
  maxLength?: number;
  minimum?: number;
  maximum?: number;
  minItems?: number;
  items?: Schema;
  default?: unknown;
  description?: string;
}
export interface ToolDefinition { name: string; scope: "read" | "write"; destructive?: boolean; description: string; inputSchema: Schema }

export const TOOLS = contract.tools as unknown as ToolDefinition[];

function typeOf(value: unknown): string[] {
  if (value === null) return ["null"];
  if (Array.isArray(value)) return ["array"];
  if (typeof value === "number") return Number.isInteger(value) ? ["integer", "number"] : ["number"];
  return [typeof value];
}

/** First problem in `value` against the subset of JSON Schema that tools.json uses, or null. */
export function validate(value: unknown, schema: Schema, path = "invoer"): string | null {
  if (schema.type) {
    const allowed = Array.isArray(schema.type) ? schema.type : [schema.type];
    if (!typeOf(value).some(t => allowed.includes(t))) return `${path} moet van type ${allowed.join(" of ")} zijn`;
  }
  if (schema.enum && !schema.enum.includes(value)) return `${path} moet een van ${schema.enum.join(", ")} zijn`;
  if (typeof value === "string") {
    if (schema.minLength !== undefined && value.length < schema.minLength) return `${path} is te kort`;
    if (schema.maxLength !== undefined && value.length > schema.maxLength) return `${path} is te lang (maximaal ${schema.maxLength} tekens)`;
  }
  if (typeof value === "number") {
    if (schema.minimum !== undefined && value < schema.minimum) return `${path} moet minstens ${schema.minimum} zijn`;
    if (schema.maximum !== undefined && value > schema.maximum) return `${path} mag hoogstens ${schema.maximum} zijn`;
  }
  if (Array.isArray(value)) {
    if (schema.minItems !== undefined && value.length < schema.minItems) return `${path} heeft minstens ${schema.minItems} waarde(n) nodig`;
    if (schema.items) {
      for (let i = 0; i < value.length; i++) {
        const problem = validate(value[i], schema.items, `${path}[${i}]`);
        if (problem) return problem;
      }
    }
  }
  if (typeOf(value)[0] === "object" && value) {
    const object = value as Record<string, unknown>;
    for (const key of schema.required ?? []) if (!(key in object)) return `${key} ontbreekt`;
    for (const [key, child] of Object.entries(object)) {
      const property = schema.properties?.[key];
      if (!property) {
        if (schema.additionalProperties === false) return `${key} is geen bekend veld`;
        continue;
      }
      const problem = validate(child, property, key);
      if (problem) return problem;
    }
  }
  return null;
}

function visibleTools(allowWrite: boolean): ToolDefinition[] {
  return TOOLS.filter(tool => allowWrite || tool.scope === "read");
}

type Id = string | number | null;
const result = (id: Id, value: unknown) => JSON.stringify({ jsonrpc: "2.0", id, result: value });
const error = (id: Id, code: number, message: string, data?: unknown) =>
  JSON.stringify({ jsonrpc: "2.0", id, error: data === undefined ? { code, message } : { code, message, data } });
const toolText = (text: string, isError: boolean, structured?: Record<string, unknown>) => ({
  resultType: "complete",
  content: [{ type: "text", text }],
  ...(isError ? { isError: true } : { structuredContent: structured }),
});

async function callTool(params: Record<string, unknown>, ctx: RouterContext): Promise<{ error: string } | { value: unknown }> {
  const tool = visibleTools(ctx.allowWrite).find(t => t.name === params.name);
  if (!tool) return { error: `Unknown tool: ${String(params.name)}` };
  const raw = params.arguments ?? {};
  const problem = validate(raw, tool.inputSchema);
  if (problem) return { value: toolText(`Ongeldige invoer: ${problem}`, true) };
  const args: Record<string, unknown> = { ...(raw as Record<string, unknown>) };
  for (const [key, property] of Object.entries(tool.inputSchema.properties ?? {})) {
    if (!(key in args) && property.default !== undefined) args[key] = property.default;
  }
  const handler = ctx.handlers[tool.name];
  try {
    if (!handler) throw new Error(`Tool ${tool.name} is niet beschikbaar.`);
    const value = await handler(args);
    const structured = value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : { result: value };
    return { value: toolText(JSON.stringify(value), false, structured) };
  } catch (failure) {
    return { value: toolText(failure instanceof Error ? failure.message : String(failure), true) };
  }
}

/** Answers one JSON-RPC line; null when no response is due (notifications, client responses). */
export async function handleMessage(line: string, ctx: RouterContext): Promise<string | null> {
  let message: unknown;
  try {
    message = JSON.parse(line);
  } catch {
    return error(null, -32700, "Parse error");
  }
  if (!message || typeof message !== "object" || Array.isArray(message)) return error(null, -32600, "Invalid Request");
  const request = message as { id?: Id; method?: unknown; params?: unknown };
  if (!("id" in request)) return null;
  const id: Id = request.id ?? null;
  if (typeof request.method !== "string") return "result" in request || "error" in request ? null : error(id, -32600, "Invalid Request");
  const params = (request.params && typeof request.params === "object" ? request.params : {}) as Record<string, unknown>;
  const meta = params._meta as Record<string, unknown> | undefined;
  const requested = meta?.["io.modelcontextprotocol/protocolVersion"];
  if (requested !== undefined && !SUPPORTED_VERSIONS.includes(requested as string)) {
    return error(id, -32022, "Unsupported protocol version", { supported: SUPPORTED_VERSIONS, requested });
  }
  switch (request.method) {
    case "initialize": {
      const asked = params.protocolVersion as string;
      return result(id, {
        resultType: "complete",
        protocolVersion: SUPPORTED_VERSIONS.includes(asked) ? asked : FALLBACK_VERSION,
        capabilities: { tools: { listChanged: false } },
        serverInfo: { name: SERVER_NAME, version: ctx.version },
        instructions: contract.instructions,
      });
    }
    case "server/discover":
      return result(id, {
        resultType: "complete",
        supportedVersions: SUPPORTED_VERSIONS,
        capabilities: { tools: {} },
        _meta: { "io.modelcontextprotocol/serverInfo": { name: SERVER_NAME, version: ctx.version } },
        instructions: contract.instructions,
        ttlMs: 0,
        cacheScope: "private",
      });
    case "ping":
      return result(id, {});
    case "tools/list":
      return result(id, {
        resultType: "complete",
        tools: visibleTools(ctx.allowWrite).map(({ scope, destructive, ...tool }) => ({
          ...tool,
          annotations: { readOnlyHint: scope === "read", destructiveHint: destructive === true, openWorldHint: false },
        })),
        ttlMs: 0,
        cacheScope: "private",
      });
    case "tools/call": {
      const outcome = await callTool(params, ctx);
      return "error" in outcome ? error(id, -32602, outcome.error) : result(id, outcome.value);
    }
    default:
      return error(id, -32601, `Method not found: ${request.method}`);
  }
}
