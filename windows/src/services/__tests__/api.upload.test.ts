import { describe, it, expect, vi, beforeEach } from "vitest";

// Mock localStorage
const localStorageMap = new Map<string, string>();
vi.stubGlobal("localStorage", {
  getItem: (key: string) => localStorageMap.get(key) ?? null,
  setItem: (key: string, value: string) => localStorageMap.set(key, value),
  removeItem: (key: string) => localStorageMap.delete(key),
  clear: () => localStorageMap.clear(),
});

// Mock Tauri invoke before importing api
const mockInvoke = vi.fn();
vi.mock("@tauri-apps/api/core", () => ({
  invoke: (...args: unknown[]) => mockInvoke(...args),
}));

// Mock auth store
const mockGetState = vi.fn();
vi.mock("../../stores/authStore", () => ({
  useAuthStore: { getState: () => mockGetState() },
}));

// Import after mocks
import { api } from "../api";

describe("uploadRecording", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    localStorageMap.clear();
    mockGetState.mockReturnValue({ token: "test-token-123" });
  });

  it("calls proxy_upload with correct arguments", async () => {
    mockInvoke.mockResolvedValueOnce({
      status: 200,
      body: JSON.stringify({ task_id: "task-abc" }),
      headers: {},
    });

    const result = await api.uploadRecording(
      "C:\\Users\\bas\\recordings\\test.wav",
      "profile-1",
      "combined"
    );

    expect(mockInvoke).toHaveBeenCalledWith("proxy_upload", {
      filePath: "C:\\Users\\bas\\recordings\\test.wav",
      uploadUrl: "https://n8n.prezent.nl/tstudio/api/transcribe",
      token: "test-token-123",
      profileId: "profile-1",
      mode: "combined",
    });
    expect(result).toEqual({ task_id: "task-abc" });
  });

  it("handles HTTP error response from server", async () => {
    mockInvoke.mockResolvedValueOnce({
      status: 413,
      body: JSON.stringify({ error: "Bestand te groot" }),
      headers: {},
    });

    await expect(
      api.uploadRecording("/path/to/big.wav", "p1", "microphone")
    ).rejects.toThrow("Bestand te groot");
  });

  it("handles Rust invoke failure (file not found)", async () => {
    mockInvoke.mockRejectedValueOnce(
      new Error("Bestand niet gevonden: /tmp/gone.wav")
    );

    await expect(
      api.uploadRecording("/tmp/gone.wav", "p1", "combined")
    ).rejects.toThrow("Bestand niet gevonden");
  });

  it("handles Rust invoke failure (empty file)", async () => {
    mockInvoke.mockRejectedValueOnce(
      new Error("Opnamebestand is leeg (0 bytes)")
    );

    await expect(
      api.uploadRecording("/tmp/empty.wav", "p1", "combined")
    ).rejects.toThrow("leeg (0 bytes)");
  });

  it("handles Rust invoke failure (network error)", async () => {
    mockInvoke.mockRejectedValueOnce(
      new Error("Upload netwerkfout: connection refused")
    );

    await expect(
      api.uploadRecording("/tmp/test.wav", "p1", "combined")
    ).rejects.toThrow("netwerkfout");
  });

  it("handles invalid JSON response from server", async () => {
    mockInvoke.mockResolvedValueOnce({
      status: 200,
      body: "not json",
      headers: {},
    });

    await expect(
      api.uploadRecording("/tmp/test.wav", "p1", "combined")
    ).rejects.toThrow("Ongeldig antwoord");
  });

  it("sends empty string token when not authenticated", async () => {
    mockGetState.mockReturnValue({ token: null });
    mockInvoke.mockResolvedValueOnce({
      status: 200,
      body: JSON.stringify({ task_id: "t1" }),
      headers: {},
    });

    await api.uploadRecording("/tmp/test.wav", "p1", "combined");

    expect(mockInvoke).toHaveBeenCalledWith("proxy_upload", expect.objectContaining({
      token: "",
    }));
  });

  it("uses custom server URL from localStorage", async () => {
    localStorageMap.set(
      "settings-store",
      JSON.stringify({ state: { server_url: "https://custom.server/api" } })
    );

    mockInvoke.mockResolvedValueOnce({
      status: 200,
      body: JSON.stringify({ task_id: "t1" }),
      headers: {},
    });

    await api.uploadRecording("/tmp/test.wav", "p1", "combined");

    expect(mockInvoke).toHaveBeenCalledWith("proxy_upload", expect.objectContaining({
      uploadUrl: "https://custom.server/api/transcribe",
    }));
  });
});

describe("uploadRecordingWithProgress", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    localStorageMap.clear();
    mockGetState.mockReturnValue({ token: "test-token-123" });
  });

  it("calls progress callback during upload", async () => {
    mockInvoke.mockResolvedValueOnce({
      status: 200,
      body: JSON.stringify({ task_id: "task-progress" }),
      headers: {},
    });

    const progress = vi.fn();
    const result = await api.uploadRecordingWithProgress(
      "/tmp/test.wav",
      "p1",
      "combined",
      progress
    );

    expect(result).toEqual({ task_id: "task-progress" });
    // Should have called progress at least for start, mid, and end
    expect(progress).toHaveBeenCalled();
    const calls = progress.mock.calls.map((c: number[][]) => c[0]);
    // Final call should be 1.0
    expect(calls[calls.length - 1]).toBe(1.0);
  });

  it("handles abort signal", async () => {
    const controller = new AbortController();
    controller.abort(); // Abort immediately

    const progress = vi.fn();

    await expect(
      api.uploadRecordingWithProgress(
        "/tmp/test.wav",
        "p1",
        "combined",
        progress,
        controller.signal
      )
    ).rejects.toThrow("Upload geannuleerd");
  });

  it("propagates Rust errors with details", async () => {
    mockInvoke.mockRejectedValueOnce({
      message: "Kan bestand niet lezen: Permission denied",
    });

    const progress = vi.fn();

    await expect(
      api.uploadRecordingWithProgress(
        "/tmp/no-access.wav",
        "p1",
        "combined",
        progress
      )
    ).rejects.toThrow("Kan bestand niet lezen");
  });

  it("handles HTTP error in progress upload", async () => {
    mockInvoke.mockResolvedValueOnce({
      status: 500,
      body: JSON.stringify({ message: "Server overbelast" }),
      headers: {},
    });

    const progress = vi.fn();

    await expect(
      api.uploadRecordingWithProgress(
        "/tmp/test.wav",
        "p1",
        "combined",
        progress
      )
    ).rejects.toThrow("Server overbelast");
  });
});
