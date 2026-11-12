type RecordingRegistration = { ready: Promise<void>; active: boolean };
let currentRecording: RecordingRegistration | null = null;
export function beginMainRecordingHandler() {
  let resolve!: () => void;
  let reject!: (error: Error) => void;
  const ready = new Promise<void>((yes, no) => { resolve = yes; reject = no; });
  void ready.catch(() => {});
  const registration = { ready, active: false };
  currentRecording = registration;
  return {
    activate: () => {
      if (currentRecording !== registration) return false;
      registration.active = true; resolve(); return true;
    },
    dispose: () => {
      registration.active = false;
      if (currentRecording === registration) currentRecording = null;
      reject(new Error("Main recording handler is unavailable"));
    },
  };
}
export async function requireMainRecordingHandler(): Promise<() => boolean> {
  const registration = currentRecording;
  if (!registration) throw new Error("Main recording handler is unavailable");
  await registration.ready;
  const current = () => currentRecording === registration && registration.active;
  if (!current()) throw new Error("Main recording handler changed");
  return current;
}
