// Task status pipeline (10 stages)
export type TaskStatus =
  | "pending"
  | "uploading"
  | "converting"
  | "transcribing"
  | "generating"
  | "completed"
  | "failed"
  | "cancelled"
  | "queued"
  | "paused";

export const TaskStatusLabels: Record<TaskStatus, string> = {
  pending: "Wachten...",
  uploading: "Uploaden...",
  converting: "Converteren...",
  transcribing: "Transcriberen...",
  generating: "Notulen genereren...",
  completed: "Voltooid",
  failed: "Mislukt",
  cancelled: "Geannuleerd",
  queued: "In wachtrij",
  paused: "Gepauzeerd",
};

// Recording modes
export type RecordingMode = "microphone" | "combined";

// Notulen providers
export type NotulenProvider = "cloud" | "ollama" | "lm-studio";

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
  extracted_title?: string;
  profile_id?: string;
  mode: RecordingMode;
  duration_seconds?: number;
  created_at: string;
  updated_at?: string;
  queue_position?: number;
}

// Completed saved transcript
export interface Transcript {
  id: string;
  title: string;
  raw_transcription?: string;
  notule_html?: string;
  duration_seconds: number;
  profile_name?: string;
  tags: string[];
  created_at: string;
  updated_at: string;
}

// Profile for meeting notes generation
export interface Profile {
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

export const DEFAULT_PROFILES: Profile[] = [
  {
    id: "zakelijk",
    name: "Zakelijk",
    system_prompt:
      "Je bent een professionele notulist. Genereer gestructureerde vergadernotulen in het Nederlands. Gebruik geen analyse of redenering. Geef direct het eindresultaat.",
    notule_prompt:
      "Maak gestructureerde notulen van deze vergadering. Gebruik kopjes voor: Aanwezigen, Agendapunten, Besluiten, Actiepunten.",
    is_default: true,
  },
  {
    id: "informeel",
    name: "Informeel",
    system_prompt:
      "Je bent een notulist voor informele vergaderingen. Schrijf in een toegankelijke stijl in het Nederlands.",
    notule_prompt:
      "Maak een beknopte samenvatting van dit gesprek. Noteer de belangrijkste punten en afspraken.",
    is_default: false,
  },
  {
    id: "technisch",
    name: "Technisch",
    system_prompt:
      "Je bent een technische notulist. Noteer technische details nauwkeurig in het Nederlands.",
    notule_prompt:
      "Maak gedetailleerde technische notulen. Noteer alle technische beslissingen, architectuurkeuzes en actiepunten.",
    is_default: false,
  },
];

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
export interface AppSettings {
  server_url: string;
  notulen_provider: NotulenProvider;
  ollama_url: string;
  ollama_model: string;
  lm_studio_url: string;
  lm_studio_model: string;
  default_profile_id: string;
  default_recording_mode: RecordingMode;
  has_completed_onboarding: boolean;
  ms365_tenant_id?: string;
  ms365_client_id?: string;
}

export const DEFAULT_SETTINGS: AppSettings = {
  server_url: "https://n8n.prezent.nl/tstudio/api",
  notulen_provider: "cloud",
  ollama_url: "http://localhost:11434",
  ollama_model: "llama3.2",
  lm_studio_url: "http://localhost:1234",
  lm_studio_model: "local-model",
  default_profile_id: "zakelijk",
  default_recording_mode: "combined",
  has_completed_onboarding: false,
};
