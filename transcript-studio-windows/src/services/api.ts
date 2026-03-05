import { invoke } from "@tauri-apps/api/core";
import type {
  LoginResponse,
  Transcript,
  Profile,
  AdminUser,
  BugReport,
  SystemHealth,
  InviteCode,
} from "../types";

/** Extract a human-readable message from any thrown value. */
function extractErrorMessage(err: unknown): string {
  if (typeof err === "string") return err;
  if (err instanceof Error) return err.message;
  // Tauri wraps Rust errors as { message: string } objects
  if (err && typeof err === "object") {
    const e = err as Record<string, unknown>;
    if (typeof e.message === "string") return e.message;
    if (typeof e.error === "string") return e.error;
    try { return JSON.stringify(err); } catch { /* */ }
  }
  return "Onbekende fout";
}

class APIService {
  private get baseUrl(): string {
    const stored = localStorage.getItem("settings-store");
    if (stored) {
      try {
        const parsed = JSON.parse(stored);
        // Zustand persist wraps state under .state key
        const url = parsed?.state?.server_url ?? parsed?.server_url;
        if (url) return url;
      } catch {
        // fall through
      }
    }
    return "https://n8n.prezent.nl";
  }

  private get token(): string | null {
    const stored = localStorage.getItem("auth-store");
    if (stored) {
      try {
        const parsed = JSON.parse(stored);
        return parsed?.state?.token ?? parsed?.token ?? null;
      } catch {
        return null;
      }
    }
    return null;
  }

  private async request<T>(
    method: string,
    path: string,
    body?: unknown
  ): Promise<T> {
    const headers: Record<string, string> = {
      "Content-Type": "application/json",
    };
    if (this.token) {
      headers["Authorization"] = `Bearer ${this.token}`;
    }

    let response: { status: number; body: string; headers: Record<string, string> };
    try {
      response = await invoke<{ status: number; body: string; headers: Record<string, string> }>(
        "proxy_request",
        {
          request: {
            url: `${this.baseUrl}${path}`,
            method,
            headers,
            body: body ? JSON.stringify(body) : undefined,
          },
        }
      );
    } catch (err) {
      throw new Error(extractErrorMessage(err));
    }

    if (response.status >= 400) {
      let errorMessage = `HTTP ${response.status}`;
      try {
        const errorData = JSON.parse(response.body);
        errorMessage = errorData.message || errorData.error || errorData.detail || errorMessage;
      } catch {
        if (response.body) errorMessage = response.body;
      }
      throw new Error(errorMessage);
    }

    if (!response.body || response.body === "") {
      return undefined as T;
    }

    try {
      return JSON.parse(response.body) as T;
    } catch {
      throw new Error(`Ongeldig JSON antwoord van server`);
    }
  }

  // Auth
  async login(email: string, password: string): Promise<LoginResponse> {
    return this.request<LoginResponse>("POST", "/tstudio/api/auth/login", {
      email,
      password,
    });
  }

  async verify2FA(tempToken: string, code: string): Promise<LoginResponse> {
    return this.request<LoginResponse>("POST", "/tstudio/api/auth/2fa/verify", {
      temp_token: tempToken,
      code,
    });
  }

  async logout(): Promise<void> {
    try {
      await this.request<void>("POST", "/tstudio/api/auth/logout");
    } catch {
      // ignore logout errors
    }
  }

  // Transcripts
  async getTranscripts(params?: {
    search?: string;
    tags?: string[];
    limit?: number;
    offset?: number;
  }): Promise<Transcript[]> {
    const query = new URLSearchParams();
    if (params?.search) query.set("search", params.search);
    if (params?.tags?.length) query.set("tags", params.tags.join(","));
    if (params?.limit) query.set("limit", params.limit.toString());
    if (params?.offset) query.set("offset", params.offset.toString());

    const path = `/tstudio/api/transcripts${query.toString() ? "?" + query : ""}`;
    try {
      const data = await this.request<Transcript[] | { items: Transcript[] }>(
        "GET",
        path
      );
      return Array.isArray(data) ? data : data.items || [];
    } catch {
      return [];
    }
  }

  async getTranscript(id: string): Promise<Transcript> {
    return this.request<Transcript>("GET", `/tstudio/api/transcripts/${id}`);
  }

  async updateTranscript(id: string, updates: Partial<Transcript>): Promise<Transcript> {
    return this.request<Transcript>("PATCH", `/tstudio/api/transcripts/${id}`, updates);
  }

  async deleteTranscript(id: string): Promise<void> {
    return this.request<void>("DELETE", `/tstudio/api/transcripts/${id}`);
  }

  async regenerateNotule(id: string, profileId: string): Promise<{ task_id: string }> {
    return this.request<{ task_id: string }>(
      "POST",
      `/tstudio/api/transcripts/${id}/regenerate`,
      { profile_id: profileId }
    );
  }

  getStreamUrl(taskId: string): string {
    return `${this.baseUrl}/tstudio/api/tasks/${taskId}/stream`;
  }

  // Upload
  async uploadRecording(
    filePath: string,
    profileId: string,
    mode: string
  ): Promise<{ task_id: string }> {
    const headers: Record<string, string> = {};
    if (this.token) {
      headers["Authorization"] = `Bearer ${this.token}`;
    }

    const response = await invoke<{ status: number; body: string }>(
      "http_upload_file",
      {
        url: `${this.baseUrl}/tstudio/api/transcribe`,
        filePath,
        fieldName: "file",
        additionalFields: { profile_id: profileId, mode },
        headers,
      }
    );

    if (response.status >= 400) {
      let errorMessage = `Upload mislukt: HTTP ${response.status}`;
      try {
        const errorData = JSON.parse(response.body);
        errorMessage = errorData.message || errorData.detail || errorMessage;
      } catch {
        // ignore
      }
      throw new Error(errorMessage);
    }

    return JSON.parse(response.body);
  }

  // Profiles
  async getProfiles(): Promise<Profile[]> {
    try {
      return await this.request<Profile[]>("GET", "/tstudio/api/profiles");
    } catch {
      return [];
    }
  }

  async createProfile(profile: Omit<Profile, "id">): Promise<Profile> {
    return this.request<Profile>("POST", "/tstudio/api/profiles", profile);
  }

  async updateProfile(id: string, updates: Partial<Profile>): Promise<Profile> {
    return this.request<Profile>("PUT", `/tstudio/api/profiles/${id}`, updates);
  }

  async deleteProfile(id: string): Promise<void> {
    return this.request<void>("DELETE", `/tstudio/api/profiles/${id}`);
  }

  // Admin
  async getAdminUsers(): Promise<AdminUser[]> {
    try {
      const data = await this.request<AdminUser[] | { items?: AdminUser[]; users?: AdminUser[] }>(
        "GET",
        "/tstudio/api/admin/users"
      );
      if (Array.isArray(data)) return data;
      return data.items || data.users || [];
    } catch {
      return [];
    }
  }

  async createAdminUser(
    email: string,
    password: string,
    name: string,
    role: "user" | "admin"
  ): Promise<AdminUser> {
    return this.request<AdminUser>("POST", "/tstudio/api/admin/users", {
      email,
      password,
      name,
      role,
    });
  }

  async deleteAdminUser(userId: string): Promise<void> {
    return this.request<void>("DELETE", `/tstudio/api/admin/users/${userId}`);
  }

  async getBugReports(): Promise<BugReport[]> {
    try {
      return await this.request<BugReport[]>("GET", "/tstudio/api/admin/bug-reports");
    } catch {
      return [];
    }
  }

  async getSystemHealth(): Promise<SystemHealth> {
    return this.request<SystemHealth>("GET", "/tstudio/api/admin/health");
  }

  async generateInviteCode(): Promise<InviteCode> {
    return this.request<InviteCode>("POST", "/tstudio/api/admin/invite-codes");
  }
}

export const api = new APIService();
