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
  raw_transcription?: string;
  notule_html?: string;
  error_message?: string;
  profile_id?: string;
  mode: RecordingMode;
  duration_seconds?: number;
  created_at: string;
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
  system_prompt: string;
  notule_prompt: string;
  notule_template?: string;
  is_default: boolean;
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
  user: User;
  requires_2fa?: boolean;
  temp_token?: string;
}

export interface TwoFactorSetup {
  qr_code: string;
  secret: string;
  backup_codes: string[];
}

// Admin
export interface AdminUser extends User {
  last_login?: string;
  transcripts_count: number;
  storage_bytes: number;
}

export interface BugReport {
  id: string;
  user_id: string;
  user_email: string;
  description: string;
  status: "open" | "in_progress" | "resolved" | "closed";
  created_at: string;
}

export interface SystemHealth {
  api_status: "ok" | "degraded" | "down";
  transcription_queue_length: number;
  active_tasks: number;
  storage_used_gb: number;
  version: string;
}

export interface InviteCode {
  code: string;
  created_by: string;
  uses_remaining: number;
  max_uses: number;
  expires_at?: string;
  created_at: string;
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
  server_url: "https://n8n.prezent.nl",
  notulen_provider: "cloud",
  ollama_url: "http://localhost:11434",
  ollama_model: "llama3.2",
  lm_studio_url: "http://localhost:1234",
  lm_studio_model: "local-model",
  default_profile_id: "zakelijk",
  default_recording_mode: "combined",
  has_completed_onboarding: false,
};
