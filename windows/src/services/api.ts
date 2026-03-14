import { invoke } from "@tauri-apps/api/core";
import { readFile } from "@tauri-apps/plugin-fs";
import { useAuthStore } from "../stores/authStore";
import type {
  LoginResponse,
  Transcript,
  TranscriptTask,
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
  PaginatedResponse,
  ProfilesResponse,
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

/** Safely extract an array from various possible response formats. */
function safeArray<T>(data: unknown): T[] {
  if (Array.isArray(data)) return data as T[];
  if (data && typeof data === "object") {
    const obj = data as Record<string, unknown>;
    // Check for common wrapper formats
    if (Array.isArray(obj.items)) return obj.items as T[];
    if (Array.isArray(obj.data)) return obj.data as T[];
    if (Array.isArray(obj.results)) return obj.results as T[];
    if (Array.isArray(obj.profiles)) return obj.profiles as T[];
    if (Array.isArray(obj.users)) return obj.users as T[];
    if (Array.isArray(obj.transcripts)) return obj.transcripts as T[];
    if (Array.isArray(obj.tasks)) return obj.tasks as T[];
    if (Array.isArray(obj.tags)) return obj.tags as T[];
  }
  return [];
}

/** Normalize a backend transcript object to our Transcript type. */
function mapTranscript(raw: unknown): Transcript {
  const r = raw as Record<string, unknown>;

  return {
    id: safeString(r.id ?? r.task_id, ""),
    title: safeString(r.title ?? r.filename, "Naamloze opname"),
    raw_transcription: safeOptionalString(r.raw_transcription, r.transcription, r.original_transcription),
    notule_html: safeOptionalString(r.notule_html, r.result),
    duration_seconds: Number(r.duration ?? r.duration_seconds ?? 0),
    profile_name: safeOptionalString(r.profile_name),
    tags: Array.isArray(r.tags) ? r.tags.filter((t): t is string => typeof t === "string") : [],
    created_at: safeString(r.created_at ?? r.date, new Date().toISOString()),
    updated_at: safeString(r.updated_at ?? r.created_at, new Date().toISOString()),
  };
}

/** Normalize a backend task object to our TranscriptTask type. */
function mapTask(raw: unknown): TranscriptTask {
  const r = raw as Record<string, unknown>;

  return {
    task_id: safeString(r.task_id ?? r.id, ""),
    status: safeString(r.status, "pending") as TranscriptTask["status"],
    progress: Number(r.progress ?? 0),
    message: safeOptionalString(r.message),
    raw_transcription: safeOptionalString(r.raw_transcription, r.transcription),
    notule_html: safeOptionalString(r.notule_html, r.result),
    error_message: safeOptionalString(r.error_message, r.error),
    filename: safeOptionalString(r.filename),
    extracted_title: safeOptionalString(r.extracted_title, r.title),
    profile_id: safeOptionalString(r.profile_id),
    mode: (safeString(r.mode, "microphone") as TranscriptTask["mode"]),
    duration_seconds: r.duration_seconds != null ? Number(r.duration_seconds) : undefined,
    created_at: safeString(r.created_at, new Date().toISOString()),
    updated_at: safeOptionalString(r.updated_at),
    queue_position: r.queue_position != null ? Number(r.queue_position) : undefined,
  };
}

class APIService {
  private cache = new Map<string, { data: unknown; ts: number }>();
  private CACHE_TTL = 3000;

  private getCached<T>(key: string): T | null {
    const entry = this.cache.get(key);
    if (entry && Date.now() - entry.ts < this.CACHE_TTL) return entry.data as T;
    return null;
  }

  private setCache(key: string, data: unknown): void {
    this.cache.set(key, { data, ts: Date.now() });
  }

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
    return "https://n8n.prezent.nl/tstudio/api";
  }

  private get token(): string | null {
    return useAuthStore.getState().token;
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

    const requestUrl = `${this.baseUrl}${path}`;
    if (import.meta.env.DEV) console.log(`[API] ${method} ${requestUrl}`);

    let response: { status: number; body: string; headers: Record<string, string> };
    try {
      response = await invoke<{ status: number; body: string; headers: Record<string, string> }>(
        "proxy_request",
        {
          request: {
            url: requestUrl,
            method,
            headers,
            body: body ? JSON.stringify(body) : undefined,
          },
        }
      );
    } catch (err) {
      throw new Error(extractErrorMessage(err));
    }

    if (import.meta.env.DEV) console.log(`[API] ${method} ${path} → ${response.status} (${response.body.length} bytes)`);

    if (response.status >= 400) {
      // Try to extract server error message first
      let serverMessage: string | null = null;
      try {
        const errorData = JSON.parse(response.body);
        const extracted = errorData.message || errorData.error || errorData.detail;
        if (typeof extracted === "string") serverMessage = extracted;
      } catch { /* no parseable body */ }

      // Dutch error messages by status code
      let errorMessage: string;
      switch (response.status) {
        case 401: errorMessage = "Sessie verlopen. Log opnieuw in."; break;
        case 403: errorMessage = "Geen toegang tot deze functie."; break;
        case 404: errorMessage = serverMessage || "Niet gevonden."; break;
        case 409: errorMessage = serverMessage || "Conflict: de gegevens zijn gewijzigd."; break;
        case 422: errorMessage = serverMessage || "Ongeldige invoer."; break;
        case 429: errorMessage = "Te veel verzoeken. Probeer het later opnieuw."; break;
        default:
          if (response.status >= 500) {
            errorMessage = "Serverfout. Probeer het later opnieuw.";
          } else {
            errorMessage = serverMessage || `Fout ${response.status}`;
          }
      }

      // Auto-logout on auth errors
      if (response.status === 401) {
        useAuthStore.getState().logout();
      }

      throw new Error(errorMessage);
    }

    if (!response.body || response.body === "") {
      return undefined as T;
    }

    try {
      return JSON.parse(response.body) as T;
    } catch {
      throw new Error(`Ongeldig JSON antwoord van server: ${response.body.substring(0, 200)}`);
    }
  }

  // Auth
  async login(email: string, password: string): Promise<LoginResponse> {
    return this.request<LoginResponse>("POST", "/auth/login", {
      username: email,
      password,
    });
  }

  async verify2FA(username: string, tempToken: string, code: string): Promise<LoginResponse> {
    return this.request<LoginResponse>("POST", "/auth/login/verify-2fa", {
      username,
      temp_token: tempToken,
      code,
    });
  }

  async logout(): Promise<void> {
    try {
      await this.request<void>("POST", "/auth/logout");
    } catch {
      // ignore logout errors
    }
  }

  // Transcripts
  async getTranscripts(params?: {
    search?: string;
    tags?: string[];
    limit?: number;
  }): Promise<Transcript[]> {
    // When a specific limit is requested (e.g. limit: 1 for latest), do a single request
    if (params?.limit) {
      const query = new URLSearchParams();
      if (params.search) query.set("search", params.search.slice(0, 255));
      if (params.tags?.length) query.set("tags", params.tags.join(","));
      query.set("limit", params.limit.toString());
      query.set("page", "1");
      query.set("sort_by", "newest");

      const path = `/transcripts?${query}`;
      const data = await this.request<unknown>("GET", path);
      return safeArray<unknown>(data).map(mapTranscript);
    }

    // No limit specified — auto-paginate to load all transcripts
    const pageSize = 100;
    let page = 1;
    const all: Transcript[] = [];

    while (true) {
      const query = new URLSearchParams();
      if (params?.search) query.set("search", params.search.slice(0, 255));
      if (params?.tags?.length) query.set("tags", params.tags.join(","));
      query.set("limit", pageSize.toString());
      query.set("page", page.toString());
      query.set("sort_by", "newest");

      const path = `/transcripts?${query}`;
      const data = await this.request<unknown>("GET", path);
      const items = safeArray<unknown>(data).map(mapTranscript);
      all.push(...items);

      // Stop if we got fewer items than the page size (last page)
      if (items.length < pageSize) break;

      // Also stop if the response included a total and we have them all
      if (data && typeof data === "object") {
        const total = (data as Record<string, unknown>).total;
        if (typeof total === "number" && all.length >= total) break;
      }

      page++;
    }

    return all;
  }

  async getTranscript(id: string): Promise<Transcript> {
    const data = await this.request<unknown>("GET", `/transcripts/${id}`);
    return mapTranscript(data);
  }

  async updateTranscript(id: string, updates: Partial<Transcript>): Promise<Transcript> {
    return this.request<Transcript>("PUT", `/transcripts/${id}`, updates);
  }

  async deleteTranscript(id: string): Promise<void> {
    return this.request<void>("DELETE", `/transcripts/${id}`);
  }

  async updateNotuleHTML(id: string, notuleHtml: string): Promise<Transcript> {
    // Get the linked note ID for this transcript
    const notesData = await this.request<{ items?: Array<{ id: string }> } | Array<{ id: string }>>(
      "GET",
      `/transcripts/${id}/notes`
    );
    // Handle both array and wrapped response formats
    const items = Array.isArray(notesData) ? notesData : notesData.items;
    const noteId = items?.[0]?.id;

    if (noteId) {
      // Update existing note via notes endpoint
      await this.request<unknown>("PUT", `/notes/${noteId}`, {
        html: notuleHtml,
      });
    } else {
      // No linked note exists — create one
      await this.request<unknown>("POST", `/notes`, {
        html: notuleHtml,
        source_file: `notule_${id}`,
      });
    }

    // Return updated transcript
    const data = await this.request<unknown>("GET", `/transcripts/${id}`);
    return mapTranscript(data);
  }

  async regenerateNotule(id: string, profileId: string): Promise<{ task_id: string }> {
    return this.request<{ task_id: string }>(
      "POST",
      `/transcripts/${id}/regenerate`,
      { profile_id: profileId }
    );
  }

  async getTaskStatus(taskId: string): Promise<{ task_id: string; status: string; progress: number }> {
    return this.request<{ task_id: string; status: string; progress: number }>("GET", `/task/${taskId}`);
  }

  getStreamUrl(taskId: string): string {
    return `${this.baseUrl}/task/${taskId}/stream`;
  }

  // Features
  async fetchFeatures(): Promise<Record<string, boolean>> {
    return this.request<Record<string, boolean>>("GET", "/features");
  }

  // YouTube transcription
  async transcribeYouTube(url: string, profileId: string): Promise<TranscriptTask> {
    const data = await this.request<unknown>("POST", "/transcribe-youtube", {
      url,
      profile_id: profileId,
    });
    return mapTask(data);
  }

  // Tasks
  async getActiveTasks(): Promise<TranscriptTask[]> {
    const data = await this.request<unknown>("GET", "/tasks/active");
    return safeArray<unknown>(data).map(mapTask);
  }

  async cancelTask(taskId: string): Promise<void> {
    await this.request<{ success: boolean }>("POST", `/task/${taskId}/cancel`);
  }

  async deleteTask(taskId: string): Promise<void> {
    await this.request<{ success: boolean }>("DELETE", `/task/${taskId}`);
  }

  // Upload — uses browser-native FormData + fetch for multipart encoding
  async uploadRecording(
    filePath: string,
    profileId: string,
    mode: string,
    signal?: AbortSignal
  ): Promise<{ task_id: string }> {
    // Read file bytes via Tauri FS plugin
    const fileBytes = await readFile(filePath);

    // Build FormData — browser handles multipart/form-data encoding
    const filename = filePath.split(/[\\/]/).pop() || "recording.wav";
    const blob = new Blob([fileBytes], { type: "audio/wav" });
    const formData = new FormData();
    formData.append("file", blob, filename);
    formData.append("profile_id", profileId);
    formData.append("mode", mode);

    if (import.meta.env.DEV) console.log(`[API] Upload ${filename} (${fileBytes.length} bytes) to ${this.baseUrl}/transcribe`);

    // Browser-native fetch — no Rust involved in upload
    const response = await fetch(`${this.baseUrl}/transcribe`, {
      method: "POST",
      headers: {
        "X-User-Token": this.token || "",
      },
      body: formData,
      signal,
    });

    if (!response.ok) {
      const errorBody = await response.text();
      if (import.meta.env.DEV) console.error("[API] Upload error:", { status: response.status, body: errorBody });

      let errorMessage = `Upload mislukt (HTTP ${response.status})`;
      try {
        const errorData = JSON.parse(errorBody);
        const extracted = errorData.message || errorData.error;
        if (typeof extracted === "string") {
          errorMessage = `Upload mislukt: ${extracted}`;
        } else if (errorData.detail) {
          if (Array.isArray(errorData.detail)) {
            const fields = errorData.detail.map((d: { loc?: string[]; msg?: string }) =>
              `${(d.loc || []).join(".")}: ${d.msg || "ongeldig"}`
            ).join("; ");
            errorMessage = `Upload mislukt: ${fields}`;
          } else if (typeof errorData.detail === "string") {
            errorMessage = `Upload mislukt: ${errorData.detail}`;
          }
        }
      } catch {
        if (errorBody.length < 200) {
          errorMessage = `Upload mislukt: ${errorBody}`;
        }
      }
      throw new Error(errorMessage);
    }

    const result = await response.json();
    if (import.meta.env.DEV) console.log(`[API] Upload complete → task_id: ${result.task_id}`);
    return result;
  }

  async uploadRecordingWithProgress(
    filePath: string,
    profileId: string,
    mode: string,
    onProgress: (fraction: number) => void,
    signal?: AbortSignal
  ): Promise<{ task_id: string }> {
    const fileBytes = await readFile(filePath);
    const filename = filePath.split(/[\\/]/).pop() || "recording.wav";
    const blob = new Blob([fileBytes], { type: "audio/wav" });
    const formData = new FormData();
    formData.append("file", blob, filename);
    formData.append("profile_id", profileId);
    formData.append("mode", mode);

    if (import.meta.env.DEV) console.log(`[API] Upload with progress ${filename} (${fileBytes.length} bytes)`);

    return new Promise((resolve, reject) => {
      const xhr = new XMLHttpRequest();
      xhr.open("POST", `${this.baseUrl}/transcribe`);
      xhr.setRequestHeader("X-User-Token", this.token || "");

      if (signal) {
        signal.addEventListener("abort", () => xhr.abort(), { once: true });
      }

      xhr.upload.onprogress = (e) => {
        if (e.lengthComputable && e.total > 0) {
          onProgress(Math.min(e.loaded / e.total, 0.99));
        }
      };

      xhr.onload = () => {
        if (xhr.status >= 200 && xhr.status < 300) {
          try {
            const result = JSON.parse(xhr.responseText);
            if (import.meta.env.DEV) console.log(`[API] Upload complete → task_id: ${result.task_id}`);
            onProgress(1.0);
            resolve(result);
          } catch {
            reject(new Error("Upload mislukt: ongeldig antwoord van server"));
          }
        } else {
          let errorMessage = `Upload mislukt (HTTP ${xhr.status})`;
          try {
            const errorData = JSON.parse(xhr.responseText);
            const extracted = errorData.message || errorData.error;
            if (typeof extracted === "string") {
              errorMessage = `Upload mislukt: ${extracted}`;
            } else if (errorData.detail) {
              if (Array.isArray(errorData.detail)) {
                const fields = errorData.detail.map((d: { loc?: string[]; msg?: string }) =>
                  `${(d.loc || []).join(".")}: ${d.msg || "ongeldig"}`
                ).join("; ");
                errorMessage = `Upload mislukt: ${fields}`;
              } else if (typeof errorData.detail === "string") {
                errorMessage = `Upload mislukt: ${errorData.detail}`;
              }
            }
          } catch {
            if (xhr.responseText.length < 200) {
              errorMessage = `Upload mislukt: ${xhr.responseText}`;
            }
          }
          reject(new Error(errorMessage));
        }
      };

      xhr.onerror = () => reject(new Error("Upload mislukt: netwerkfout"));
      xhr.onabort = () => reject(new DOMException("Upload geannuleerd", "AbortError"));

      xhr.send(formData);
    });
  }

  // Profiles
  async getProfiles(): Promise<Profile[]> {
    try {
      const data = await this.request<Profile[] | ProfilesResponse>("GET", "/profiles/accessible");
      return safeArray<Profile>(data);
    } catch {
      return [];
    }
  }

  async createProfile(profile: Omit<Profile, "id">): Promise<Profile> {
    const response = await this.request<{ success: boolean; profile: Profile } | { id: string } & Partial<Profile>>(
      "POST",
      "/profiles/me",
      profile
    );
    // Handle both { success, profile } and { id, ...profile } formats
    if ("profile" in response && response.profile) return response.profile;
    return response as Profile;
  }

  async updateProfile(id: string, updates: Partial<Profile>): Promise<Profile> {
    await this.request<{ success: boolean }>("PUT", `/profiles/me/${id}`, updates);
    return { id, ...updates } as Profile;
  }

  async deleteProfile(id: string): Promise<void> {
    return this.request<void>("DELETE", `/profiles/me/${id}`);
  }

  // Admin
  async getAdminUsers(): Promise<AdminUser[]> {
    const cached = this.getCached<AdminUser[]>("admin-users");
    if (cached) return cached;
    try {
      const data = await this.request<{ items?: AdminUser[] }>(
        "GET",
        "/admin/users"
      );
      const users = safeArray<AdminUser>(data);
      this.setCache("admin-users", users);
      return users;
    } catch (err) {
      if (import.meta.env.DEV) console.error("[API] getAdminUsers error:", err);
      return [];
    }
  }

  async createAdminUser(
    email: string,
    password: string,
    name: string,
    role: "user" | "admin"
  ): Promise<AdminUser> {
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      throw new Error("Ongeldig e-mailadres");
    }
    if (password.length < 8) {
      throw new Error("Wachtwoord moet minimaal 8 tekens bevatten");
    }
    if (!["user", "admin"].includes(role)) {
      throw new Error("Ongeldige rol");
    }
    return this.request<AdminUser>("POST", "/admin/users", {
      username: email,
      password,
      name,
      role,
    });
  }

  async deleteAdminUser(userId: string): Promise<void> {
    return this.request<void>("DELETE", `/admin/users/${userId}`);
  }

  async resetUserPassword(userId: string, password: string): Promise<void> {
    return this.request<void>("POST", `/admin/users/${userId}/password`, {
      password,
    });
  }

  async resetUser2FA(userId: string): Promise<void> {
    return this.request<void>("POST", `/admin/users/${userId}/2fa/reset`);
  }

  async getFeedback(): Promise<AdminFeedback[]> {
    const cached = this.getCached<AdminFeedback[]>("admin-feedback");
    if (cached) return cached;
    try {
      const data = await this.request<AdminFeedback[] | PaginatedResponse<AdminFeedback>>(
        "GET",
        "/admin/feedback"
      );
      const items = safeArray<AdminFeedback>(data);
      this.setCache("admin-feedback", items);
      return items;
    } catch {
      return [];
    }
  }

  async updateFeedback(id: string, status: string, response?: string): Promise<void> {
    return this.request<void>("PUT", `/admin/feedback/${id}`, {
      status,
      ...(response ? { admin_response: response } : {}),
    });
  }

  async deleteFeedback(id: string): Promise<void> {
    return this.request<void>("DELETE", `/admin/feedback/${id}`);
  }

  async getFeedbackPendingCount(): Promise<number> {
    try {
      const data = await this.request<unknown>("GET", "/admin/feedback/pending-count");
      if (data && typeof data === "object") {
        const obj = data as Record<string, unknown>;
        // Backend sends pending_count
        if (typeof obj.pending_count === "number") return obj.pending_count;
        if (typeof obj.count === "number") return obj.count;
        if (typeof obj.pending === "number") return obj.pending;
      }
      return 0;
    } catch {
      return 0;
    }
  }

  async getMySettings(): Promise<{ ms365_client_id?: string; ms365_tenant_id?: string }> {
    try {
      return await this.request<{ ms365_client_id?: string; ms365_tenant_id?: string }>(
        "GET",
        "/settings/me"
      ) ?? {};
    } catch {
      return {};
    }
  }

  async getAdminSettings(): Promise<{ ms365_client_id?: string; ms365_tenant_id?: string }> {
    try {
      return await this.request<{ ms365_client_id?: string; ms365_tenant_id?: string }>(
        "GET",
        "/admin/settings"
      ) ?? {};
    } catch {
      return {};
    }
  }

  async updateAdminSettings(ms365ClientId?: string, ms365TenantId?: string): Promise<void> {
    const payload: Record<string, string> = {};
    if (ms365ClientId) payload["ms365_client_id"] = ms365ClientId;
    if (ms365TenantId) payload["ms365_tenant_id"] = ms365TenantId;
    await this.request<void>("POST", "/admin/settings", payload);
  }

  async getSystemHealth(): Promise<SystemHealth> {
    const cached = this.getCached<SystemHealth>("system-health");
    if (cached) return cached;
    try {
      const raw = await this.request<Record<string, unknown>>("GET", "/health");
      const health: SystemHealth = {
        api_status: (raw.api_status ?? raw.status ?? "unknown") as SystemHealth["api_status"],
        transcription_queue_length: Number(raw.transcription_queue_length ?? raw.queue_length ?? 0) || 0,
        active_tasks: Number(raw.active_tasks ?? 0) || 0,
        storage_used_gb: Number(raw.storage_used_gb ?? 0) || 0,
        version: String(raw.version ?? "unknown"),
        model: raw.model as string | undefined,
        device: raw.device as string | undefined,
        max_upload_size_mb: Number(raw.max_upload_size_mb ?? 0) || 0,
      };
      this.setCache("system-health", health);
      return health;
    } catch {
      return {
        api_status: "down",
        transcription_queue_length: 0,
        active_tasks: 0,
        storage_used_gb: 0,
        version: "unknown",
      };
    }
  }

  async getDashboardMetrics(days: number = 7): Promise<Record<string, unknown>> {
    try {
      return await this.request<Record<string, unknown>>("GET", `/admin/dashboard/metrics?days=${days}`);
    } catch {
      return {};
    }
  }

  async getAdminErrors(params: {
    limit?: number;
    severity?: string;
    user_id?: string;
    search?: string;
    start_date?: string;
    end_date?: string;
  } = {}): Promise<unknown[]> {
    try {
      const query = new URLSearchParams();
      if (params.limit) query.set("limit", String(params.limit));
      if (params.severity) query.set("severity", params.severity);
      if (params.user_id) query.set("user_id", params.user_id);
      if (params.search) query.set("search", params.search);
      if (params.start_date) query.set("start_date", params.start_date);
      if (params.end_date) query.set("end_date", params.end_date);
      const qs = query.toString();
      const data = await this.request<unknown[] | PaginatedResponse<unknown>>("GET", `/admin/errors${qs ? `?${qs}` : ""}`);
      return safeArray<unknown>(data);
    } catch {
      return [];
    }
  }

  async getAdminActivity(params: {
    limit?: number;
    user_id?: string;
    action_type?: string;
    search?: string;
    start_date?: string;
    end_date?: string;
  } = {}): Promise<unknown[]> {
    try {
      const query = new URLSearchParams();
      if (params.limit) query.set("limit", String(params.limit));
      if (params.user_id) query.set("user_id", params.user_id);
      if (params.action_type) query.set("action_type", params.action_type);
      if (params.search) query.set("search", params.search);
      if (params.start_date) query.set("start_date", params.start_date);
      if (params.end_date) query.set("end_date", params.end_date);
      const qs = query.toString();
      const data = await this.request<unknown[] | PaginatedResponse<unknown>>("GET", `/admin/activity${qs ? `?${qs}` : ""}`);
      return safeArray<unknown>(data);
    } catch {
      return [];
    }
  }

  async generateInviteCode(maxUses: number = 1, expiresHours: number = 48): Promise<InviteCode> {
    return this.request<InviteCode>("POST", "/admin/invites", {
      max_uses: maxUses,
      expires_hours: expiresHours,
    });
  }

  async getInviteCodes(): Promise<InviteCode[]> {
    try {
      const data = await this.request<InviteCode[] | PaginatedResponse<InviteCode>>("GET", "/admin/invites");
      return safeArray<InviteCode>(data);
    } catch {
      return [];
    }
  }

  async deleteInviteCode(code: string): Promise<void> {
    return this.request<void>("DELETE", `/admin/invites/${code}`);
  }

  // Auth — password change
  async changePassword(currentPassword: string, newPassword: string): Promise<void> {
    return this.request<void>("POST", "/auth/change-password", {
      current_password: currentPassword,
      new_password: newPassword,
    });
  }

  // Auth — 2FA management
  async get2FAStatus(): Promise<TwoFAStatus> {
    return this.request<TwoFAStatus>("GET", "/auth/2fa/status");
  }

  async setup2FA(): Promise<TwoFASetupResponse> {
    return this.request<TwoFASetupResponse>("POST", "/auth/2fa/setup");
  }

  async verify2FASetup(code: string): Promise<TwoFAVerifyResponse> {
    return this.request<TwoFAVerifyResponse>("POST", "/auth/2fa/verify-setup", { code });
  }

  async disable2FA(password: string): Promise<void> {
    return this.request<void>("POST", "/auth/2fa/disable", { password });
  }

  async regenerateBackupCodes(): Promise<TwoFAVerifyResponse> {
    return this.request<TwoFAVerifyResponse>("POST", "/auth/2fa/regenerate-backup-codes");
  }

  // Auth — password reset
  async requestPasswordReset(email: string): Promise<void> {
    return this.request<void>("POST", "/auth/password-reset/request", { username: email });
  }

  async verifyPasswordReset(email: string, code: string): Promise<{ reset_token: string }> {
    return this.request<{ reset_token: string }>("POST", "/auth/password-reset/verify", {
      username: email,
      code,
    });
  }

  async completePasswordReset(resetToken: string, newPassword: string): Promise<void> {
    return this.request<void>("POST", "/auth/password-reset/complete", {
      reset_token: resetToken,
      new_password: newPassword,
    });
  }

  // Profiles — visibility, public, copy
  async setProfileVisibility(id: string, isPublic: boolean): Promise<void> {
    return this.request<void>("PATCH", `/profiles/me/${id}/visibility`, { is_public: isPublic });
  }

  async getPublicProfiles(search?: string): Promise<Profile[]> {
    try {
      const query = search ? `?search=${encodeURIComponent(search)}` : "";
      const data = await this.request<Profile[] | ProfilesResponse>("GET", `/profiles/public${query}`);
      return safeArray<Profile>(data);
    } catch {
      return [];
    }
  }

  async copyProfile(id: string): Promise<Profile> {
    const data = await this.request<{ profile?: Profile } & Profile>("POST", `/profiles/${id}/copy`);
    return data.profile ?? data;
  }

  // Transcripts — tags
  async getAllTags(): Promise<string[]> {
    try {
      const data = await this.request<{ tags?: string[] } | string[]>("GET", "/transcripts/tags");
      if (Array.isArray(data)) return data as string[];
      return (data?.tags ?? []) as string[];
    } catch {
      return [];
    }
  }

  async updateTranscriptTags(id: string, add: string[], remove: string[]): Promise<void> {
    return this.request<void>("PATCH", `/transcripts/${id}/tags`, { add, remove });
  }

  // Transcripts — bulk operations
  async bulkDeleteTranscripts(ids: string[]): Promise<void> {
    return this.request<void>("POST", "/transcripts/bulk-delete", { ids });
  }

  async bulkExportTranscripts(ids: string[], format: "txt" | "docx" = "txt"): Promise<Blob> {
    const response = await this.request<unknown>("POST", `/transcripts/bulk-export?format=${format}`, { ids });
    return response as unknown as Blob;
  }

  async bulkAddTags(ids: string[], tags: string[]): Promise<void> {
    return this.request<void>("POST", "/transcripts/bulk-tags", { ids, tags, action: "add" });
  }

  // Feedback (user-facing)
  async submitFeedback(feedback: FeedbackSubmission): Promise<void> {
    return this.request<void>("POST", "/feedback", feedback);
  }

  async getMyFeedback(): Promise<UserFeedback[]> {
    try {
      const data = await this.request<UserFeedback[] | PaginatedResponse<UserFeedback>>("GET", "/feedback/my");
      return safeArray<UserFeedback>(data);
    } catch {
      return [];
    }
  }

  async getUnreadFeedbackCount(): Promise<number> {
    try {
      const data = await this.request<unknown>("GET", "/feedback/unread-count");
      if (data && typeof data === "object") {
        const obj = data as Record<string, unknown>;
        return typeof obj.count === "number" ? obj.count : typeof obj.unread === "number" ? obj.unread : 0;
      }
      return 0;
    } catch {
      return 0;
    }
  }

  async markFeedbackRead(id: string): Promise<void> {
    return this.request<void>("POST", `/feedback/${id}/mark-read`);
  }

  // Version
  async checkVersion(): Promise<{ minimum_version: string; current_version: string; is_supported?: boolean } | null> {
    try {
      return await this.request<{ minimum_version: string; current_version: string; is_supported?: boolean }>("GET", `/version`);
    } catch {
      return null;
    }
  }
}

export const api = new APIService();
