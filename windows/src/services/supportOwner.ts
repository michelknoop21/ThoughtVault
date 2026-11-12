import { emitTo, listen } from "@tauri-apps/api/event";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { enqueueFailure } from "./crashReporter";
import { isSupportReportDurable, useSupportStore } from "../stores/supportStore";
import { WIDGET_ACK_EVENT, WIDGET_FAILURE_EVENT, WIDGET_FAILURES } from "./widgetSupport";
import type { WidgetAck, WidgetFailure } from "./widgetSupport";

let ready: Promise<void> | null = null;
export async function requireSupportOwner(): Promise<() => boolean> {
  const startup = ready;
  if (!startup) throw new Error("Support owner is not ready");
  await startup;
  const current = () => ready === startup;
  if (!current()) throw new Error("Support owner changed");
  return current;
}

export function startSupportOwner(): () => void {
  let disposed = false;
  let unlisten: (() => void) | undefined;
  let serial = Promise.resolve();
  // shortcut: last 256 ACKs survive only this owner lifetime; no crash-safe exactly-once transfer.
  const accepted = new Map<string, WidgetAck["outcome"]>();
  const remember = (id: string, outcome: WidgetAck["outcome"]) => {
    accepted.delete(id);
    accepted.set(id, outcome);
    if (accepted.size > 256) accepted.delete(accepted.keys().next().value!);
  };
  const startup = (async () => {
    if (getCurrentWindow().label !== "main") throw new Error("Only main can own support");
    const stop = await listen<WidgetFailure>(WIDGET_FAILURE_EVENT, ({ payload }) => {
      // Never serialize or accept arbitrary caller error text, stage or extra fields.
      if (!payload || typeof payload !== "object" || Object.keys(payload).length !== 2 || typeof payload.id !== "string" || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(payload.id)
          || typeof payload.code !== "string" || !Object.prototype.hasOwnProperty.call(WIDGET_FAILURES, payload.code)) return;
      const { id, code } = payload;
      serial = serial.then(async () => {
        if (disposed) return;
        let outcome = accepted.get(id);
        if (!outcome) {
          if (isSupportReportDurable(id)) outcome = "queued";
          else {
            const result = await enqueueFailure("opnemen", WIDGET_FAILURES[code], `widget_${code}`, id);
            if (disposed || result === "failed") return; // Failed storage/scrubbing never receives an ACK.
            outcome = result;
          }
          remember(id, outcome);
        }
        if (disposed) return;
        // Cache before ACK/flush so a lost ACK cannot re-enqueue an already flushed item.
        await emitTo("recording-widget", WIDGET_ACK_EVENT, { id, outcome } satisfies WidgetAck).catch(() => {});
        if (!disposed && outcome === "queued") void useSupportStore.getState().flushQueue().catch(() => {});
      }).catch(() => {});
    });
    if (disposed) stop(); else unlisten = stop;
  })();
  ready = startup;
  void startup.catch(() => {});
  return () => { disposed = true; unlisten?.(); if (ready === startup) ready = null; };
}
