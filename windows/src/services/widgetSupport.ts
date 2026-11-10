import { emitTo, listen } from "@tauri-apps/api/event";

export const WIDGET_FAILURE_EVENT = "support-widget-failure";
export const WIDGET_ACK_EVENT = "support-widget-ack";
// Stop is reported from the native recording-error event by the future C8 main hook.
export const WIDGET_FAILURES = {
  pause_failed: "Pauzeren mislukt",
  resume_failed: "Hervatten mislukt",
} as const;
export type WidgetFailureCode = keyof typeof WIDGET_FAILURES;
export interface WidgetFailure { id: string; code: WidgetFailureCode }
export interface WidgetAck { id: string; outcome: "queued" | "discarded" }

// Keep the returned promise alive through ACK; false means delivery was not confirmed.
export async function handoffWidgetFailure(code: WidgetFailureCode): Promise<boolean> {
  const payload: WidgetFailure = { id: crypto.randomUUID(), code };
  let unlisten: (() => void) | undefined;
  let timer: ReturnType<typeof setInterval> | undefined;
  try {
    return await new Promise<boolean>((resolve, reject) => {
      let attempts = 0;
      const send = () => {
        if (++attempts > 5) { resolve(false); return; }
        void emitTo("main", WIDGET_FAILURE_EVENT, payload).catch(() => {});
      };
      void listen<WidgetAck>(WIDGET_ACK_EVENT, ({ payload: ack }) => {
        if (ack?.id === payload.id && (ack.outcome === "queued" || ack.outcome === "discarded")) resolve(true);
      }).then(stop => {
        unlisten = stop;
        timer = setInterval(send, 1000);
        send();
      }, reject);
    });
  } catch { return false; }
  finally { if (timer) clearInterval(timer); unlisten?.(); }
}
