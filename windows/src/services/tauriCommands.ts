import { invoke } from "@tauri-apps/api/core";

type RecordingErrorDiagnostic = "expected" | "native-owned";
class RecordingCommandError extends Error {
  constructor(message: string, readonly diagnostic: RecordingErrorDiagnostic) {
    super(message);
  }
}

function normalizeRecordingRejection(error: unknown): never {
  if (typeof error === "object" && error !== null &&
      Object.getPrototypeOf(error) === Object.prototype &&
      Object.keys(error).length === 2 &&
      "message" in error && typeof error.message === "string" &&
      "diagnostic" in error &&
      (error.diagnostic === "expected" || error.diagnostic === "native-owned")) {
    throw new RecordingCommandError(error.message, error.diagnostic);
  }
  throw error;
}

/** Unknown IPC/permission failures must still be reported by the caller. */
export function shouldReportRecordingFailure(error: unknown): boolean {
  return !(error instanceof RecordingCommandError);
}

/** Feed this into each caller's existing String/instanceof Error UI logic. */
export function recordingErrorForUI(error: unknown): unknown {
  return error instanceof RecordingCommandError ? error.message : error;
}

export interface AudioDevice {
  id: string;
  name: string;
  is_default: boolean;
  is_input: boolean;
}

export interface RecordingResult {
  file_path: string;
  duration_seconds: number;
}

export interface NetworkStatus {
  is_online: boolean;
  connection_type: string;
}

export interface MeetingApp {
  name: string;
  process_name: string;
  is_running: boolean;
}

export interface SystemSpecs {
  cpu: string;
  architecture: string;
  memory_gb: number;
  threads: number;
  os_version: string;
  free_storage_gb: number | null;
}

export interface RecordingFile {
  path: string;
  filename: string;
  size_bytes: number;
  created_at: number;
  duration_seconds: number | null;
}

// Audio commands
export async function getAudioDevices(): Promise<AudioDevice[]> {
  return invoke<AudioDevice[]>("get_audio_devices");
}

export async function startRecording(
  deviceId: string | null,
  mode: string,
  outputDir: string
): Promise<string> {
  return invoke<string>("start_recording", {
    deviceId,
    mode,
    outputDir,
  }).catch(normalizeRecordingRejection);
}

export async function stopRecording(): Promise<RecordingResult> {
  return invoke<RecordingResult>("stop_recording").catch(normalizeRecordingRejection);
}

export async function pauseRecording(): Promise<void> {
  return invoke<void>("pause_recording").catch(normalizeRecordingRejection);
}

export async function resumeRecording(): Promise<void> {
  return invoke<void>("resume_recording").catch(normalizeRecordingRejection);
}

// Credential commands
export async function storeCredential(key: string, value: string): Promise<void> {
  return invoke("store_credential", { key, value });
}

export async function loadCredential(key: string): Promise<string | null> {
  return invoke<string | null>("load_credential", { key });
}

export async function deleteCredential(key: string): Promise<void> {
  return invoke("delete_credential", { key });
}

// Filesystem commands
export async function listRecordings(directory: string): Promise<RecordingFile[]> {
  return invoke<RecordingFile[]>("list_recordings", { directory });
}

export async function deleteRecording(filePath: string): Promise<void> {
  return invoke("delete_recording", { filePath });
}

export async function cleanupOldRecordings(
  directory: string,
  maxAgeDays: number = 7
): Promise<number> {
  return invoke<number>("cleanup_old_recordings", { directory, maxAgeDays });
}

// System commands
export async function getNetworkStatus(): Promise<NetworkStatus> {
  return invoke<NetworkStatus>("get_network_status");
}

export async function detectMeetingApps(): Promise<MeetingApp[]> {
  return invoke<MeetingApp[]>("detect_meeting_apps");
}

export async function getAppVersion(): Promise<string> {
  return invoke<string>("get_app_version");
}

// Filesystem commands (extended)
export async function getRecordingsDir(): Promise<string> {
  return invoke<string>("get_recordings_dir");
}

export async function importAudio(sourcePath: string): Promise<string> {
  return invoke<string>("import_audio", { sourcePath });
}

/**
 * One-time migration of recordings from %APPDATA% (Roaming) to %LOCALAPPDATA% (Local).
 * Idempotent — call once on app startup. No-op on macOS/Linux.
 * Returns the number of files moved.
 */
export async function migrateRecordingsDir(): Promise<number> {
  return invoke<number>("migrate_recordings_dir");
}

export async function concatenateWavFiles(
  inputPaths: string[],
  outputPath: string
): Promise<string> {
  return invoke<string>("concatenate_wav_files", { inputPaths, outputPath });
}
