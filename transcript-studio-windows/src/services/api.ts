import { invoke } from "@tauri-apps/api/core";
import type {
  LoginResponse,
  Transcript,
  Profile,
  AdminUser,
  AdminFeedback,
  SystemHealth,
  InviteCode,
  TwoFAStatus,
  TwoFASetupResponse,
  TwoFAVerifyResponse,
  FeedbackSubmission,
  UserFeedback,
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

/** Safely extract a string value, returning fallback for objects/null. */
function safeString(val: unknown, fallback: string): string {
  if (typeof val === "string") return val;
  if (val == null) return fallback;
  if (typeof val === "number") return String(val);
  return fallback;
}

/** Safely extract an optional string value. */
function safeOptionalString(...vals: unknown[]): string | undefined {
  for (const val of vals) {
    if (typeof val === "string") return val;
  }
  return undefined;
}

/** Normalize a backend transcript object to our Transcript type. */
function mapTranscript(raw: unknown): Transcript {
  const r = raw as Record<string, unknown>;

  return {
    id: safeString(r.id ?? r.task_id, ""),
    title: safeString(r.title ?? r.filename, "Naamloze opname"),
    raw_transcription: safeOptionalString(r.raw_transcription, r.transcription),
    notule_html: safeOptionalString(r.notule_html, r.result),
    duration_seconds: Number(r.duration ?? r.duration_seconds ?? 0),
    profile_name: safeOptionalString(r.profile_name),
    tags: Array.isArray(r.tags) ? r.tags.filter((t): t is string => typeof t === "string") : [],
    created_at: safeString(r.created_at ?? r.date, new Date().toISOString()),
    updated_at: safeString(r.updated_at ?? r.created_at, new Date().toISOString()),
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
      headers["X-User-Token"] = this.token;
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
        const extracted = errorData.message || errorData.error || errorData.detail;
        errorMessage = (typeof extracted === "string" ? extracted : null) || errorMessage;
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
    return this.request<Transcript>("PUT", `/tstudio/api/transcripts/${id}`, updates);
  }

  async deleteTranscript(id: string): Promise<void> {
    return this.request<void>("DELETE", `/tstudio/api/transcripts/${id}`);
  }

  async updateNotuleHTML(id: string, notuleHtml: string): Promise<Transcript> {
    // Get the linked note ID for this transcript
    const notesData = await this.request<{ items?: Array<{ id: string }> }>(
      "GET",
      `/tstudio/api/transcripts/${id}/notes`
    );
    const noteId = notesData.items?.[0]?.id;

    if (noteId) {
      // Update existing note via notes endpoint
      await this.request<unknown>("PUT", `/tstudio/api/notes/${noteId}`, {
        html: notuleHtml,
      });
    } else {
      // No linked note exists — create one
      await this.request<unknown>("POST", `/tstudio/api/notes`, {
        html: notuleHtml,
        source_file: `notule_${id}`,
      });
    }

    // Return updated transcript
    const data = await this.request<unknown>("GET", `/tstudio/api/transcripts/${id}`);
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
      headers["X-User-Token"] = this.token;
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
      let errorMessage = `Upload mislukt (HTTP ${response.status})`;
      try {
        const errorData = JSON.parse(response.body);
        const extracted = errorData.message || errorData.detail || errorData.error;
        if (typeof extracted === "string") {
          errorMessage = `Upload mislukt: ${extracted}`;
        }
      } catch {
        if (response.body && response.body.length < 200) {
          errorMessage = `Upload mislukt: ${response.body}`;
        }
      }
      console.error("[API] Upload error:", { status: response.status, body: response.body });
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

  // Auth — password change
  async changePassword(currentPassword: string, newPassword: string): Promise<void> {
    return this.request<void>("POST", "/tstudio/api/auth/change-password", {
      current_password: currentPassword,
      new_password: newPassword,
    });
  }

  // Auth — 2FA management
  async get2FAStatus(): Promise<TwoFAStatus> {
    return this.request<TwoFAStatus>("GET", "/tstudio/api/auth/2fa/status");
  }

  async setup2FA(): Promise<TwoFASetupResponse> {
    return this.request<TwoFASetupResponse>("POST", "/tstudio/api/auth/2fa/setup");
  }

  async verify2FASetup(code: string): Promise<TwoFAVerifyResponse> {
    return this.request<TwoFAVerifyResponse>("POST", "/tstudio/api/auth/2fa/verify-setup", { code });
  }

  async disable2FA(password: string): Promise<void> {
    return this.request<void>("POST", "/tstudio/api/auth/2fa/disable", { password });
  }

  async regenerateBackupCodes(): Promise<TwoFAVerifyResponse> {
    return this.request<TwoFAVerifyResponse>("POST", "/tstudio/api/auth/2fa/regenerate-backup-codes");
  }

  // Auth — password reset
  async requestPasswordReset(email: string): Promise<void> {
    return this.request<void>("POST", "/tstudio/api/auth/password-reset/request", { username: email });
  }

  async verifyPasswordReset(email: string, code: string): Promise<{ reset_token: string }> {
    return this.request<{ reset_token: string }>("POST", "/tstudio/api/auth/password-reset/verify", {
      username: email,
      code,
    });
  }

  async completePasswordReset(resetToken: string, newPassword: string): Promise<void> {
    return this.request<void>("POST", "/tstudio/api/auth/password-reset/complete", {
      reset_token: resetToken,
      new_password: newPassword,
    });
  }

  // Profiles — visibility, public, copy
  async setProfileVisibility(id: string, isPublic: boolean): Promise<void> {
    return this.request<void>("PATCH", `/tstudio/api/profiles/me/${id}/visibility`, { is_public: isPublic });
  }

  async getPublicProfiles(search?: string): Promise<Profile[]> {
    const query = search ? `?search=${encodeURIComponent(search)}` : "";
    const data = await this.request<{ profiles?: Profile[] } | Profile[]>("GET", `/tstudio/api/profiles/public${query}`);
    return Array.isArray(data) ? data : data.profiles ?? [];
  }

  async copyProfile(id: string): Promise<Profile> {
    const data = await this.request<{ profile?: Profile } & Profile>("POST", `/tstudio/api/profiles/${id}/copy`);
    return data.profile ?? data;
  }

  // Transcripts — tags
  async getAllTags(): Promise<string[]> {
    const data = await this.request<{ tags?: string[] } | string[]>("GET", "/tstudio/api/transcripts/tags");
    return Array.isArray(data) ? data : data.tags ?? [];
  }

  async updateTranscriptTags(id: string, add: string[], remove: string[]): Promise<void> {
    return this.request<void>("PATCH", `/tstudio/api/transcripts/${id}/tags`, { add, remove });
  }

  // Transcripts — bulk operations
  async bulkDeleteTranscripts(ids: string[]): Promise<void> {
    return this.request<void>("POST", "/tstudio/api/transcripts/bulk-delete", { ids });
  }

  async bulkExportTranscripts(ids: string[], format: "txt" | "docx" = "txt"): Promise<Blob> {
    const response = await this.request<unknown>("POST", `/tstudio/api/transcripts/bulk-export?format=${format}`, { ids });
    return response as unknown as Blob;
  }

  async bulkAddTags(ids: string[], tags: string[]): Promise<void> {
    return this.request<void>("POST", "/tstudio/api/transcripts/bulk-tags", { ids, tags, action: "add" });
  }

  // Feedback (user-facing)
  async submitFeedback(feedback: FeedbackSubmission): Promise<void> {
    return this.request<void>("POST", "/tstudio/api/feedback", feedback);
  }

  async getMyFeedback(): Promise<UserFeedback[]> {
    try {
      return await this.request<UserFeedback[]>("GET", "/tstudio/api/feedback/my");
    } catch {
      return [];
    }
  }

  async getUnreadFeedbackCount(): Promise<number> {
    try {
      const data = await this.request<{ count: number }>("GET", "/tstudio/api/feedback/unread-count");
      return data.count;
    } catch {
      return 0;
    }
  }

  async markFeedbackRead(id: string): Promise<void> {
    return this.request<void>("POST", `/tstudio/api/feedback/${id}/mark-read`);
  }

  // Version
  async checkVersion(): Promise<{ minimum_version: string; version: string } | null> {
    try {
      return await this.request<{ minimum_version: string; version: string }>("GET", `/tstudio/api/version`);
    } catch {
      return null;
    }
  }
}

export const api = new APIService();
