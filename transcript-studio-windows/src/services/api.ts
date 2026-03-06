import { invoke } from "@tauri-apps/api/core";
import type {
  LoginResponse,
  Transcript,
  Profile,
  AdminUser,
  AdminFeedback,
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

/** Normalize a backend transcript object to our Transcript type. */
function mapTranscript(raw: unknown): Transcript {
  const r = raw as Record<string, unknown>;
  const rawTranscription =
    (r.raw_transcription as string | undefined)
    ?? (r.transcription as string | undefined);
  const notuleHtml =
    (r.notule_html as string | undefined)
    ?? (r.result as string | undefined);

  return {
    id: String(r.id ?? r.task_id ?? ""),
    title: String(r.title ?? r.filename ?? "Naamloze opname"),
    raw_transcription: rawTranscription,
    notule_html: notuleHtml,
    duration_seconds: Number(r.duration ?? r.duration_seconds ?? 0),
    profile_name: (r.profile_name as string) ?? undefined,
    tags: Array.isArray(r.tags) ? r.tags.map(String) : [],
    created_at: String(r.created_at ?? r.date ?? new Date().toISOString()),
    updated_at: String(r.updated_at ?? r.created_at ?? new Date().toISOString()),
  };
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
      username: email,
      password,
    });
  }

  async verify2FA(username: string, tempToken: string, code: string): Promise<LoginResponse> {
    return this.request<LoginResponse>("POST", "/tstudio/api/auth/login/verify-2fa", {
      username,
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
    query.set("page", "1");
    query.set("sort_by", "newest");

    const path = `/tstudio/api/transcripts${query.toString() ? "?" + query : ""}`;
    const data = await this.request<unknown>("GET", path);
    const raw: unknown[] = Array.isArray(data)
      ? data
      : (data as Record<string, unknown>).items as unknown[]
        || (data as Record<string, unknown>).transcripts as unknown[]
        || [];
    return raw.map(mapTranscript);
  }

  async getTranscript(id: string): Promise<Transcript> {
    const data = await this.request<unknown>("GET", `/tstudio/api/transcripts/${id}`);
    return mapTranscript(data);
  }

  async updateTranscript(id: string, updates: Partial<Transcript>): Promise<Transcript> {
    return this.request<Transcript>("PATCH", `/tstudio/api/transcripts/${id}`, updates);
  }

  async deleteTranscript(id: string): Promise<void> {
    return this.request<void>("DELETE", `/tstudio/api/transcripts/${id}`);
  }

  async updateNotuleHTML(id: string, notuleHtml: string): Promise<Transcript> {
    const data = await this.request<unknown>("PATCH", `/tstudio/api/transcripts/${id}`, {
      notule_html: notuleHtml,
    });
    return mapTranscript(data);
  }

  async regenerateNotule(id: string, profileId: string): Promise<{ task_id: string }> {
    return this.request<{ task_id: string }>(
      "POST",
      `/tstudio/api/transcripts/${id}/regenerate`,
      { profile_id: profileId }
    );
  }

  getStreamUrl(taskId: string): string {
    return `${this.baseUrl}/tstudio/api/task/${taskId}/stream`;
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
      const response = await this.request<{ profiles: Profile[] }>("GET", "/tstudio/api/profiles/accessible");
      return response.profiles ?? [];
    } catch {
      return [];
    }
  }

  async createProfile(profile: Omit<Profile, "id">): Promise<Profile> {
    const response = await this.request<{ success: boolean; profile: Profile }>("POST", "/tstudio/api/profiles/me", profile);
    return response.profile;
  }

  async updateProfile(id: string, updates: Partial<Profile>): Promise<Profile> {
    await this.request<{ success: boolean }>("PUT", `/tstudio/api/profiles/me/${id}`, updates);
    return { id, ...updates } as Profile;
  }

  async deleteProfile(id: string): Promise<void> {
    return this.request<void>("DELETE", `/tstudio/api/profiles/me/${id}`);
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
      username: email,
      password,
      name,
      role,
    });
  }

  async deleteAdminUser(userId: string): Promise<void> {
    return this.request<void>("DELETE", `/tstudio/api/admin/users/${userId}`);
  }

  async resetUserPassword(userId: string, password: string): Promise<void> {
    return this.request<void>("POST", `/tstudio/api/admin/users/${userId}/password`, {
      password,
    });
  }

  async resetUser2FA(userId: string): Promise<void> {
    return this.request<void>("POST", `/tstudio/api/admin/users/${userId}/2fa/reset`);
  }

  async getFeedback(): Promise<AdminFeedback[]> {
    try {
      return await this.request<AdminFeedback[]>("GET", "/tstudio/api/admin/feedback");
    } catch {
      return [];
    }
  }

  async updateFeedback(id: string, status: string, response?: string): Promise<void> {
    return this.request<void>("PUT", `/tstudio/api/admin/feedback/${id}`, {
      status,
      ...(response ? { response } : {}),
    });
  }

  async deleteFeedback(id: string): Promise<void> {
    return this.request<void>("DELETE", `/tstudio/api/admin/feedback/${id}`);
  }

  async getFeedbackPendingCount(): Promise<number> {
    const data = await this.request<{ count: number }>("GET", "/tstudio/api/admin/feedback/pending-count");
    return data.count;
  }

  async getMySettings(): Promise<{ ms365_client_id?: string; ms365_tenant_id?: string }> {
    return this.request<{ ms365_client_id?: string; ms365_tenant_id?: string }>(
      "GET",
      "/tstudio/api/settings/me"
    );
  }

  async getSystemHealth(): Promise<SystemHealth> {
    return this.request<SystemHealth>("GET", "/tstudio/api/health");
  }

  async getDashboardMetrics(days: number = 7): Promise<Record<string, unknown>> {
    return this.request<Record<string, unknown>>("GET", `/tstudio/api/admin/dashboard/metrics?days=${days}`);
  }

  async getAdminErrors(limit: number = 50): Promise<unknown[]> {
    return this.request<unknown[]>("GET", `/tstudio/api/admin/errors?limit=${limit}`);
  }

  async getAdminActivity(limit: number = 50): Promise<unknown[]> {
    return this.request<unknown[]>("GET", `/tstudio/api/admin/activity?limit=${limit}`);
  }

  async generateInviteCode(maxUses: number = 1, expiresHours: number = 48): Promise<InviteCode> {
    return this.request<InviteCode>("POST", "/tstudio/api/admin/invites", {
      max_uses: maxUses,
      expires_hours: expiresHours,
    });
  }

  async getInviteCodes(): Promise<InviteCode[]> {
    try {
      return await this.request<InviteCode[]>("GET", "/tstudio/api/admin/invites");
    } catch {
      return [];
    }
  }

  async deleteInviteCode(code: string): Promise<void> {
    return this.request<void>("DELETE", `/tstudio/api/admin/invites/${code}`);
  }
}

export const api = new APIService();
