/** A chat completion as read from the response body. */
export interface ChatCompletion {
  text: string;
  finishReason?: string;
  usage?: unknown;
  /** Error code an SSE stream reported after HTTP 200 (the routed provider sends these mid-stream). */
  streamError?: string;
}

/** Reads one JSON chat completion, or the SSE body of a `stream: true` request: deltas joined, the last finish
 * reason and usage kept, comment lines (keep-alives) skipped. A server that ignores `stream` still answers JSON. */
export function readChatCompletion(body: string): ChatCompletion {
  if (body.trimStart().startsWith("{")) {
    const parsed = JSON.parse(body);
    const choice = parsed.choices?.[0];
    return { text: typeof choice?.message?.content === "string" ? choice.message.content : "", finishReason: choice?.finish_reason ?? undefined, usage: parsed.usage };
  }
  const result: ChatCompletion = { text: "" };
  let done = false;
  for (const line of body.split("\n")) {
    if (!line.startsWith("data:")) continue;
    const data = line.slice(5).trim();
    if (data === "[DONE]") { done = true; break; }
    let chunk;
    try { chunk = JSON.parse(data); } catch { continue; }
    if (chunk.usage) result.usage = chunk.usage;
    if (chunk.error) result.streamError = String(chunk.error.code ?? "onbekend");
    const choice = chunk.choices?.[0];
    if (typeof choice?.delta?.content === "string") result.text += choice.delta.content;
    if (choice?.finish_reason) result.finishReason = choice.finish_reason;
  }
  if (!done && !result.finishReason && !result.streamError) result.streamError = "onvolledig";
  if (result.finishReason === "error" && !result.streamError) result.streamError = "onbekend";
  return result;
}
