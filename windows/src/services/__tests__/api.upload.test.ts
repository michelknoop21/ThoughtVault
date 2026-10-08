import { beforeEach, expect, it, vi } from "vitest";
const invoke = vi.hoisted(() => vi.fn());
vi.mock("@tauri-apps/api/core", () => ({ invoke }));
import { api } from "../api";

beforeEach(() => {
  invoke.mockClear();
  localStorage.setItem("settings-store", JSON.stringify({ state: { processing_mode: "cloud", server_url: "https://old.server/api" } }));
});

it("blocks server requests and both upload paths even with old cloud settings", async () => {
  await expect(api.login("colleague@example.test", "unused")).rejects.toThrow("uitsluitend lokaal");
  await expect(api.uploadRecording("C:\\Recordings\\meeting.wav", "standaard", "combined")).rejects.toThrow("uitsluitend lokaal");
  await expect(api.uploadRecordingWithProgress("C:\\Recordings\\meeting.wav", "standaard", "combined", vi.fn())).rejects.toThrow("uitsluitend lokaal");
  expect(invoke).not.toHaveBeenCalled();
});
