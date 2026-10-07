// Task status pipeline (10 stages)
export type TaskStatus =
  | "pending"
  | "uploading"
  | "downloading"
  | "converting"
  | "transcribing"
  | "generating"
  | "completed"
  | "failed"
  | "cancelled"
  | "queued"
  | "paused"
  | "error";

export const TaskStatusLabels: Record<TaskStatus, string> = {
  pending: "Wachten...",
  uploading: "Uploaden...",
  downloading: "Downloaden...",
  converting: "Converteren...",
  transcribing: "Transcriberen...",
  generating: "Notulen genereren...",
  completed: "Voltooid",
  failed: "Mislukt",
  cancelled: "Geannuleerd",
  queued: "In wachtrij",
  paused: "Gepauzeerd",
  error: "Fout",
};

// Recording modes
export type RecordingMode = "microphone" | "combined";

// Notulen providers
export type NotulenProvider = "cloud" | "ollama" | "lm-studio" | "ollama-cloud" | "openai-compatible";

// Processing mode: "cloud" = upload to backend, "local" = transcribe + generate
// fully on-device (Whisper + Ollama/LM Studio). Mirrors the macOS processingMode.
export type ProcessingMode = "cloud" | "local";

// Available local Whisper models (GGML). Maps 1:1 to ggml-<id>.bin filenames.
export const WHISPER_MODELS: { id: string; label: string; size: string }[] = [
  { id: "small", label: "Small: sneller, minder accuraat", size: "~466 MB" },
  { id: "medium", label: "Medium: aanbevolen", size: "~1,5 GB" },
  { id: "large-v3", label: "Large v3: beste kwaliteit, traag op CPU", size: "~3 GB" },
];

// In-progress recording/processing task
export interface TranscriptTask {
  task_id: string;
  status: TaskStatus;
  progress: number; // 0-100
  message?: string;
  raw_transcription?: string;
  notule_html?: string;
  error_message?: string;
  filename?: string;
  local_audio_path?: string;
  extracted_title?: string;
  profile_id?: string;
  source_type?: string;
  source_url?: string;
  mode: RecordingMode;
  duration_seconds?: number;
  created_at: string;
  updated_at?: string;
  queue_position?: number;
  username?: string;
}

// Completed saved transcript
export interface Transcript {
  document_style?: import("./services/documentStyle").DocumentStyle;
  id: string;
  title: string;
  raw_transcription?: string;
  notule_html?: string;
  preview?: string;
  has_notes?: boolean;
  has_transcription?: boolean;
  duration_seconds: number;
  profile_name?: string;
  tags: string[];
  created_at: string;
  updated_at: string;
}

// Person profile for self-identification and attribution (Phase 1+)
// NOTE: This is NOT the same as Profile (notule-style template below).
// isSelf==true records the installing user; isInternal defaults to true.
export interface PersonProfile {
  id: string;
  name: string;
  role: string;
  organization: string;
  aliases: string[];
  meetingTypes: string[];
  expertiseTags: string[];
  emails: string[];        // Primary dedup key for directory entries (D-02)
  isSelf: boolean;
  isInternal: boolean | null;  // null = onbekend, true = intern, false = extern (D-01)
  createdAt: string;  // ISO-8601
  updatedAt: string;  // ISO-8601
}

// Profile for meeting notes generation
export interface Profile {
  document_style?: import("./services/documentStyle").DocumentStyle;
  id: string;
  name: string;
  description?: string;
  icon?: string;
  system_prompt?: string;
  notule_prompt?: string;
  output_template?: string;  // Backend uses output_template
  notule_template?: string;  // Frontend alias for compatibility
  is_default?: boolean;
  isDefault?: boolean;
  is_public?: boolean;       // Backend uses is_public
  isOwn?: boolean;
  isPublic?: boolean;
  user_id?: string;
  count?: number;            // For profile list endpoint
  limit?: number;            // For profile list endpoint
}

import profileTemplates from "./data/profileTemplates.json";

export const DEFAULT_PROFILES: Profile[] = profileTemplates.map((entry) => ({
  id: entry.id,
  name: entry.name,
  description: entry.description,
  icon: entry.emoji,
  system_prompt: entry.systemPrompt,
  notule_prompt: entry.notulePrompt,
  output_template: entry.template,
  is_default: true,
}));

// Authentication
export interface User {
  id: string;
  email: string;
  name: string;
  role: "user" | "admin";
  is_active: boolean;
  created_at: string;
}

export interface LoginResponse {
  token: string;
  user_id: string;
  role: "user" | "admin";
  requires_2fa?: boolean;
  temp_token?: string;
}

export interface TwoFactorSetup {
  qr_code: string;
  secret: string;
  backup_codes: string[];
}

// Admin
// Backend sends AdminUser with these exact field names:
// - id, username (this is the email!), name, role
// - created_at, updated_at, last_login
// - twofa_enabled, note_count, invite_code_used
export interface AdminUser {
  id: string;
  username?: string;  // Backend sends 'username' which is the email address
  name?: string;
  role: string;
  created_at?: string;
  updated_at?: string;
  last_login?: string;
  twofa_enabled?: boolean;
  note_count?: number;
  invite_code_used?: string;

  // Frontend convenience property (computed from username)
  email?: string;  // Alias for username (not sent by backend)
  transcripts_count?: number;  // Alias for note_count
  storage_bytes?: number;  // Not in backend, kept for legacy
}

export interface BugReport {
  id: string;
  user_id: string;
  user_email: string;
  description: string;
  status: "open" | "in_progress" | "resolved" | "closed";
  created_at: string;
}

export interface AdminFeedback {
  id: string;
  category: string;
  status: string;
  title: string;
  description: string;
  user_id?: string;
  username?: string;
  created_at?: string;
  updated_at?: string;
  response?: string;  // Frontend uses 'response' (backend accepts this in PUT)
  admin_response?: string;  // Backend sends 'admin_response' in GET
  admin_user_id?: string;
  resolved_at?: string;
  response_read_at?: string;
}

export interface SystemHealth {
  api_status: "ok" | "degraded" | "down" | "unknown";
  transcription_queue_length: number;
  active_tasks: number;
  storage_used_gb: number;
  version: string;
  model?: string;
  device?: string;
  max_upload_size_mb?: number;
}

export interface InviteCode {
  code: string;
  created_by?: string;  // Backend may send 'created_by'
  uses_remaining?: number;  // Backend sends 'uses_remaining'
  max_uses?: number;
  expires_at?: string;
  created_at?: string;
}

// Admin stats (dashboard metrics)
export interface AdminStats {
  total_users: number;
  total_notes: number;
  transcriptions_today: number;
  errors_7d: number;
}

// Admin errors
export interface AdminError {
  id: string;
  error_type?: string;
  endpoint?: string;
  method?: string;
  error_message?: string;
  error_detail?: string;
  status_code?: number;
  severity?: string;
  user_id?: string;
  username?: string;
  created_at?: string;
}

// Admin activity
export interface AdminActivity {
  id: string;
  action_type: string;
  user_id?: string;
  details?: string;
  created_at?: string;
}

// Calendar / Microsoft 365
export interface CalendarEvent {
  id: string;
  title: string;
  start: string;
  end: string;
  join_url?: string;
  platform?: "teams" | "zoom" | "meet" | "webex" | "goto" | "whereby" | "jitsi" | "other";
  organizer?: string;
  attendees?: string[];
}

// Offline queue
export interface QueuedUpload {
  id: string;
  file_path: string;
  profile_id: string;
  mode: RecordingMode;
  created_at: string;
  retry_count: number;
  file_size_bytes?: number;
  recording_duration_secs?: number;
  file_name?: string;
  last_error?: string;
  // ISO timestamp; queue worker skips this item until now() >= next_retry_at.
  // Absent on legacy items — those are treated as immediately ready.
  next_retry_at?: string;
}

// 2FA
export interface TwoFAStatus {
  enabled: boolean;
  backup_codes_remaining?: number;
}

export interface TwoFASetupResponse {
  qr_code: string;
  secret: string;
  totp_secret?: string;  // Backend may use totp_secret
}

export interface TwoFAVerifyResponse {
  backup_codes: string[];
  message?: string;
}

// Feedback (user-facing)
export interface FeedbackSubmission {
  category: "bug" | "feature" | "general";
  title: string;
  description: string;
}

export interface UserFeedback {
  id: string;
  category: string;
  title: string;
  description: string;
  status: string;
  response?: string;
  created_at: string;
}

// Version check
export interface VersionCheck {
  minimum_version: string;
  current_version: string;
  is_supported: boolean;
}

// API response wrappers for different backend response formats
export interface PaginatedResponse<T> {
  items?: T[];
  total?: number;
  limit?: number;
  offset?: number;
}

export interface ProfilesResponse {
  profiles?: Profile[];
}

// Settings
export interface CloudAIConfiguration { id: string; name: string; base_url: string; model: string; }
export interface AppSettings {
  cloud_providers: CloudAIConfiguration[];
  selected_cloud_provider: string;
  ollama_cloud_model: string;
  server_url: string;
  processing_mode: ProcessingMode;
  whisper_model: string;
  notulen_provider: NotulenProvider;
  ollama_url: string;
  ollama_model: string;
  ollama_api_key: string;  // For Ollama Cloud (https://ollama.com); empty = local
  lm_studio_url: string;
  lm_studio_model: string;
  default_profile_id: string;
  default_recording_mode: RecordingMode;
  has_completed_onboarding: boolean;
  check_for_updates: boolean;
  dismissed_update_version: string;
  ms365_tenant_id?: string;
  ms365_client_id?: string;
  obsidian_enabled: boolean;
  obsidian_base_url: string;
  obsidian_vault_path: string;
  obsidian_api_key: string;
}

export const DEFAULT_SETTINGS: AppSettings = {
  cloud_providers: [],
  selected_cloud_provider: "",
  ollama_cloud_model: "",
  server_url: "https://n8n.prezent.nl/tstudio/api",
  processing_mode: "local",
  whisper_model: "medium",
  notulen_provider: "ollama",
  ollama_url: "http://localhost:11434",
  ollama_model: "llama3.2",
  ollama_api_key: "",
  lm_studio_url: "http://localhost:1234",
  lm_studio_model: "local-model",
  default_profile_id: "standaard",
  default_recording_mode: "combined",
  has_completed_onboarding: false,
  check_for_updates: false,
  dismissed_update_version: "",
  obsidian_enabled: false,
  obsidian_base_url: "https://127.0.0.1:27124",
  obsidian_vault_path: "Notulen",
  obsidian_api_key: "",
};
