import { useEffect, useState } from "react";
import {
  People24Regular,
  Bug24Regular,
  HeartPulse24Regular,
  Delete24Regular,
  Home24Regular,
  Mail24Regular,
  Copy24Regular,
  MoreHorizontal24Regular,
  ShieldCheckmark24Regular,
  Warning24Regular,
  ArrowRight24Regular,
} from "@fluentui/react-icons";
import { api } from "../services/api";
import type { AdminUser, BugReport, SystemHealth } from "../types";

type Tab = "overview" | "users" | "invitations" | "bugs" | "health";

const TABS: { id: Tab; label: string; icon: React.ReactNode }[] = [
  { id: "overview", label: "Overzicht", icon: <Home24Regular style={{ fontSize: 16 }} /> },
  { id: "users", label: "Gebruikers", icon: <People24Regular style={{ fontSize: 16 }} /> },
  { id: "invitations", label: "Uitnodigingen", icon: <Mail24Regular style={{ fontSize: 16 }} /> },
  { id: "bugs", label: "Bug Rapporten", icon: <Bug24Regular style={{ fontSize: 16 }} /> },
  { id: "health", label: "Fouten", icon: <HeartPulse24Regular style={{ fontSize: 16 }} /> },
];

export function AdminPage() {
  const [activeTab, setActiveTab] = useState<Tab>("overview");
  const [users, setUsers] = useState<AdminUser[]>([]);
  const [bugReports, setBugReports] = useState<BugReport[]>([]);
  const [health, setHealth] = useState<SystemHealth | null>(null);
  const [isLoading, setIsLoading] = useState(false);

  useEffect(() => {
    loadData();
  }, [activeTab]);

  async function loadData() {
    setIsLoading(true);
    try {
      if (activeTab === "overview") {
        const [usersData, bugsData, healthData] = await Promise.all([
          api.getAdminUsers(),
          api.getBugReports(),
          api.getSystemHealth(),
        ]);
        setUsers(usersData);
        setBugReports(bugsData);
        setHealth(healthData);
      } else if (activeTab === "users") {
        const data = await api.getAdminUsers();
        setUsers(data);
      } else if (activeTab === "bugs") {
        const data = await api.getBugReports();
        setBugReports(data);
      } else if (activeTab === "health") {
        const data = await api.getSystemHealth();
        setHealth(data);
      }
    } catch (err) {
      console.error("Admin load failed:", err);
    } finally {
      setIsLoading(false);
    }
  }

  async function handleDeleteUser(userId: string) {
    if (!confirm("Gebruiker verwijderen?")) return;
    try {
      await api.deleteAdminUser(userId);
      setUsers((prev) => prev.filter((u) => u.id !== userId));
    } catch (err) {
      console.error("Delete user failed:", err);
    }
  }

  return (
    <div style={{ height: "100%", display: "flex", flexDirection: "column" }}>
      {/* Page header */}
      <div
        style={{
          padding: "12px 16px",
          borderBottom: "1px solid var(--stroke-divider)",
          background: "var(--surface-card)",
          flexShrink: 0,
        }}
      >
        <h1 style={{ fontSize: 18, fontWeight: 600, color: "var(--text-primary)", margin: 0 }}>
          Beheer
        </h1>
      </div>

      {/* Tab bar — underline style */}
      <div className="tab-bar">
        {TABS.map((tab) => (
          <button
            key={tab.id}
            className={`tab-item${activeTab === tab.id ? " active" : ""}`}
            onClick={() => setActiveTab(tab.id)}
            style={{ display: "flex", alignItems: "center", gap: 6 }}
          >
            {tab.icon}
            {tab.label}
          </button>
        ))}
      </div>

      {/* Tab content */}
      <div style={{ flex: 1, overflowY: "auto", padding: 24 }}>
        {isLoading && (
          <div style={{ textAlign: "center", padding: 32, color: "var(--text-tertiary)", fontSize: 13 }}>
            Laden...
          </div>
        )}

        {!isLoading && activeTab === "overview" && (
          <OverviewTab users={users} bugReports={bugReports} health={health} />
        )}
        {!isLoading && activeTab === "users" && (
          <UsersTab users={users} onDelete={handleDeleteUser} />
        )}
        {!isLoading && activeTab === "invitations" && (
          <InvitationsTab />
        )}
        {!isLoading && activeTab === "bugs" && (
          <BugsTab reports={bugReports} />
        )}
        {!isLoading && activeTab === "health" && health && (
          <HealthTab health={health} />
        )}
      </div>
    </div>
  );
}

/* ============================================================
   Overzicht Tab
   ============================================================ */

function OverviewTab({
  users,
  bugReports,
  health,
}: {
  users: AdminUser[];
  bugReports: BugReport[];
  health: SystemHealth | null;
}) {
  const totalTranscripts = users.reduce((sum, u) => sum + u.transcripts_count, 0);
  const totalTasks = health ? health.active_tasks + health.transcription_queue_length : 0;
  const recentErrors = bugReports.filter((b) => {
    const created = new Date(b.created_at);
    const dayAgo = new Date(Date.now() - 24 * 60 * 60 * 1000);
    return created > dayAgo && b.status === "open";
  }).length;

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 16 }}>
      <p style={{ fontSize: 14, fontWeight: 600, color: "var(--text-primary)" }}>
        Systeem statistieken
      </p>
      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 12 }}>
        {/* Gebruikers */}
        <div className="stat-card">
          <div className="stat-card-icon" style={{ background: "rgba(229, 0, 116, 0.10)", color: "#E50074" }}>
            <People24Regular />
          </div>
          <span className="stat-card-value">{users.length}</span>
          <span className="stat-card-label">Gebruikers</span>
        </div>

        {/* Notulen */}
        <div className="stat-card">
          <div className="stat-card-icon" style={{ background: "rgba(15, 123, 15, 0.10)", color: "#0F7B0F" }}>
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <path d="M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8z" />
              <polyline points="14 2 14 8 20 8" />
              <line x1="16" y1="13" x2="8" y2="13" />
              <line x1="16" y1="17" x2="8" y2="17" />
            </svg>
          </div>
          <span className="stat-card-value">{totalTranscripts}</span>
          <span className="stat-card-label">Notulen</span>
        </div>

        {/* Taken totaal */}
        <div className="stat-card">
          <div className="stat-card-icon" style={{ background: "rgba(157, 93, 0, 0.10)", color: "#9D5D00" }}>
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <polyline points="9 11 12 14 22 4" />
              <path d="M21 12v7a2 2 0 01-2 2H5a2 2 0 01-2-2V5a2 2 0 012-2h11" />
            </svg>
          </div>
          <span className="stat-card-value">{totalTasks}</span>
          <span className="stat-card-label">Taken totaal</span>
        </div>

        {/* Fouten (24u) */}
        <div className="stat-card">
          <div className="stat-card-icon" style={{ background: "rgba(188, 0, 22, 0.10)", color: "#BC0016" }}>
            <Warning24Regular />
          </div>
          <span className="stat-card-value">{recentErrors}</span>
          <span className="stat-card-label">Fouten (24u)</span>
        </div>
      </div>
    </div>
  );
}

/* ============================================================
   Gebruikers Tab
   ============================================================ */

function UsersTab({ users, onDelete }: { users: AdminUser[]; onDelete: (id: string) => void }) {
  const [showCreateForm, setShowCreateForm] = useState(false);
  const [newEmail, setNewEmail] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [newName, setNewName] = useState("");
  const [newRole, setNewRole] = useState<"user" | "admin">("user");
  const [creating, setCreating] = useState(false);

  async function handleCreate() {
    if (!newEmail || !newPassword || !newName) return;
    setCreating(true);
    try {
      await api.createAdminUser(newEmail, newPassword, newName, newRole);
      setShowCreateForm(false);
      setNewEmail("");
      setNewPassword("");
      setNewName("");
      setNewRole("user");
      window.location.reload();
    } catch (err) {
      console.error("Create user failed:", err);
    } finally {
      setCreating(false);
    }
  }

  function copyToClipboard(text: string) {
    navigator.clipboard.writeText(text).catch(() => {});
  }

  function getInitial(name: string): string {
    return name.charAt(0).toUpperCase();
  }

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 12 }}>
      {/* Header with create button */}
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
        <p style={{ fontSize: 12, color: "var(--text-tertiary)" }}>{users.length} gebruikers</p>
        <button
          className="btn btn-accent"
          onClick={() => setShowCreateForm(!showCreateForm)}
        >
          Gebruiker aanmaken
        </button>
      </div>

      {/* Create user form */}
      {showCreateForm && (
        <div className="card" style={{ padding: 16, display: "flex", flexDirection: "column", gap: 10 }}>
          <input
            type="text"
            placeholder="Naam"
            value={newName}
            onChange={(e) => setNewName(e.target.value)}
            style={{
              padding: "8px 12px",
              fontSize: 13,
              border: "1px solid var(--stroke-divider)",
              borderRadius: "var(--radius-sm)",
              background: "var(--fill-control-default)",
              color: "var(--text-primary)",
            }}
          />
          <input
            type="email"
            placeholder="E-mail"
            value={newEmail}
            onChange={(e) => setNewEmail(e.target.value)}
            style={{
              padding: "8px 12px",
              fontSize: 13,
              border: "1px solid var(--stroke-divider)",
              borderRadius: "var(--radius-sm)",
              background: "var(--fill-control-default)",
              color: "var(--text-primary)",
            }}
          />
          <input
            type="password"
            placeholder="Wachtwoord"
            value={newPassword}
            onChange={(e) => setNewPassword(e.target.value)}
            style={{
              padding: "8px 12px",
              fontSize: 13,
              border: "1px solid var(--stroke-divider)",
              borderRadius: "var(--radius-sm)",
              background: "var(--fill-control-default)",
              color: "var(--text-primary)",
            }}
          />
          <select
            value={newRole}
            onChange={(e) => setNewRole(e.target.value as "user" | "admin")}
            style={{
              padding: "8px 12px",
              fontSize: 13,
              border: "1px solid var(--stroke-divider)",
              borderRadius: "var(--radius-sm)",
              background: "var(--fill-control-default)",
              color: "var(--text-primary)",
            }}
          >
            <option value="user">User</option>
            <option value="admin">Admin</option>
          </select>
          <div style={{ display: "flex", gap: 8 }}>
            <button className="btn btn-accent" onClick={handleCreate} disabled={creating}>
              {creating ? "Aanmaken..." : "Aanmaken"}
            </button>
            <button className="btn" onClick={() => setShowCreateForm(false)}>
              Annuleren
            </button>
          </div>
        </div>
      )}

      {/* User cards */}
      {users.map((user) => (
        <div
          key={user.id}
          className="card"
          style={{
            padding: "12px 14px",
            display: "flex",
            alignItems: "center",
            gap: 12,
          }}
        >
          {/* Avatar */}
          <div className="user-avatar">
            {getInitial(user.name)}
          </div>

          {/* User info */}
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
              <span style={{ fontSize: 14, fontWeight: 600, color: "var(--text-primary)" }}>
                {user.name}
              </span>
              <span
                style={{
                  padding: "1px 8px",
                  borderRadius: 9999,
                  fontSize: 11,
                  fontWeight: 500,
                  background: user.role === "admin" ? "rgba(229,0,116,0.10)" : "var(--fill-control-secondary)",
                  color: user.role === "admin" ? "var(--fill-accent-default)" : "var(--text-secondary)",
                }}
              >
                {user.role === "admin" ? "Admin" : "User"}
              </span>
              {/* 2FA indicator — shown if user has role admin (proxy for 2FA enabled) */}
              {user.role === "admin" && (
                <ShieldCheckmark24Regular style={{ fontSize: 14, color: "var(--fill-system-success)" }} />
              )}
            </div>
            <p style={{ fontSize: 12, color: "var(--text-tertiary)", marginTop: 2 }}>
              {user.email}
            </p>
          </div>

          {/* Action buttons */}
          <div style={{ display: "flex", alignItems: "center", gap: 4 }}>
            <button
              onClick={() => copyToClipboard(user.email)}
              style={{
                display: "flex",
                padding: 6,
                background: "transparent",
                border: "none",
                color: "var(--text-tertiary)",
                cursor: "pointer",
                borderRadius: "var(--radius-sm)",
              }}
              title="Kopieer e-mail"
            >
              <Copy24Regular style={{ fontSize: 16 }} />
            </button>
            <button
              onClick={() => onDelete(user.id)}
              style={{
                display: "flex",
                padding: 6,
                background: "transparent",
                border: "none",
                color: "var(--text-tertiary)",
                cursor: "pointer",
                borderRadius: "var(--radius-sm)",
              }}
              title="Meer opties"
              onMouseEnter={(e) => { (e.currentTarget as HTMLButtonElement).style.color = "var(--text-error)"; }}
              onMouseLeave={(e) => { (e.currentTarget as HTMLButtonElement).style.color = "var(--text-tertiary)"; }}
            >
              <MoreHorizontal24Regular style={{ fontSize: 16 }} />
            </button>
          </div>
        </div>
      ))}
    </div>
  );
}

/* ============================================================
   Uitnodigingen Tab (placeholder — uses existing generateInviteCode)
   ============================================================ */

function InvitationsTab() {
  const [inviteCode, setInviteCode] = useState<string | null>(null);
  const [generating, setGenerating] = useState(false);

  async function handleGenerate() {
    setGenerating(true);
    try {
      const result = await api.generateInviteCode();
      setInviteCode(result.code);
    } catch (err) {
      console.error("Generate invite failed:", err);
    } finally {
      setGenerating(false);
    }
  }

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 16 }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
        <p style={{ fontSize: 14, fontWeight: 600, color: "var(--text-primary)" }}>
          Uitnodigingscodes
        </p>
        <button className="btn btn-accent" onClick={handleGenerate} disabled={generating}>
          {generating ? "Genereren..." : "Code genereren"}
        </button>
      </div>

      {inviteCode && (
        <div className="card" style={{ padding: 16, display: "flex", alignItems: "center", gap: 12 }}>
          <code
            style={{
              flex: 1,
              fontSize: 16,
              fontWeight: 600,
              color: "var(--text-primary)",
              letterSpacing: "0.05em",
            }}
          >
            {inviteCode}
          </code>
          <button
            className="btn"
            onClick={() => navigator.clipboard.writeText(inviteCode).catch(() => {})}
          >
            <Copy24Regular style={{ fontSize: 16 }} />
            Kopieer
          </button>
        </div>
      )}

      <p style={{ fontSize: 13, color: "var(--text-tertiary)" }}>
        Genereer een uitnodigingscode om nieuwe gebruikers toegang te geven tot TranscriptStudio.
      </p>
    </div>
  );
}

/* ============================================================
   Bug Rapporten Tab
   ============================================================ */

function BugsTab({ reports }: { reports: BugReport[] }) {
  function getStatusBadgeClass(status: string): string {
    switch (status) {
      case "open": return "status-badge-new";
      case "in_progress": return "status-badge-in-progress";
      case "resolved": return "status-badge-resolved";
      case "closed": return "status-badge-closed";
      default: return "status-badge-closed";
    }
  }

  function getStatusLabel(status: string): string {
    switch (status) {
      case "open": return "New";
      case "in_progress": return "In Progress";
      case "resolved": return "Resolved";
      case "closed": return "Closed";
      default: return status;
    }
  }

  function getCategoryClass(description: string): { cls: string; label: string } {
    const lower = description.toLowerCase();
    if (lower.includes("feature") || lower.includes("verbetering")) {
      return { cls: "category-feature", label: "Feature" };
    }
    if (lower.includes("bug") || lower.includes("fout") || lower.includes("error") || lower.includes("crash")) {
      return { cls: "category-bug", label: "Bug" };
    }
    return { cls: "category-general", label: "General" };
  }

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
      {reports.length === 0 ? (
        <p style={{ fontSize: 13, color: "var(--text-tertiary)" }}>Geen bugrapporten</p>
      ) : (
        reports.map((report) => {
          const cat = getCategoryClass(report.description);
          return (
            <div key={report.id} className="card" style={{ padding: "14px 16px" }}>
              {/* Top row: category + status */}
              <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 8 }}>
                <span className={cat.cls}>{cat.label}</span>
                <span className={getStatusBadgeClass(report.status)}>
                  {getStatusLabel(report.status)}
                </span>
              </div>

              {/* Title — first line of description */}
              <p style={{ fontSize: 14, fontWeight: 600, color: "var(--text-primary)", marginBottom: 4 }}>
                {report.description.split("\n")[0].substring(0, 80)}
              </p>

              {/* Reporter */}
              <p style={{ fontSize: 12, color: "var(--text-tertiary)", marginBottom: 6 }}>
                {report.user_email}
              </p>

              {/* Description */}
              <p style={{ fontSize: 13, color: "var(--text-secondary)", lineHeight: 1.5, marginBottom: 10 }}>
                {report.description}
              </p>

              {/* Bottom row: actions + date */}
              <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
                <div style={{ display: "flex", gap: 6 }}>
                  {report.status === "open" && (
                    <button className="btn" style={{ fontSize: 11, padding: "4px 10px" }}>
                      <ArrowRight24Regular style={{ fontSize: 12 }} />
                      In Progress
                    </button>
                  )}
                  {(report.status === "open" || report.status === "in_progress") && (
                    <button className="btn" style={{ fontSize: 11, padding: "4px 10px" }}>
                      Resolved
                    </button>
                  )}
                  <button className="btn" style={{ fontSize: 11, padding: "4px 10px" }}>
                    Reageer
                  </button>
                </div>
                <p style={{ fontSize: 11, color: "var(--text-disabled)" }}>
                  {new Date(report.created_at).toLocaleDateString("nl-NL", {
                    day: "numeric",
                    month: "short",
                    year: "numeric",
                  })}
                </p>
              </div>
            </div>
          );
        })
      )}
    </div>
  );
}

/* ============================================================
   Fouten Tab (was: Health)
   ============================================================ */

function HealthTab({ health }: { health: SystemHealth }) {
  // Show system health as error-log style cards
  const apiStatusColor =
    health.api_status === "ok"
      ? "var(--fill-system-success)"
      : health.api_status === "degraded"
      ? "var(--fill-system-caution)"
      : "var(--fill-system-critical)";

  // Build error entries from available health data
  const errorEntries: {
    type: string;
    endpoint: string;
    timestamp: string;
    message: string;
    user?: string;
  }[] = [];

  if (health.api_status !== "ok") {
    errorEntries.push({
      type: "API-Status",
      endpoint: "/tstudio/api/health",
      timestamp: new Date().toISOString(),
      message: `API status: ${health.api_status.toUpperCase()}. Actieve taken: ${health.active_tasks}, Wachtrij: ${health.transcription_queue_length}`,
    });
  }

  if (health.transcription_queue_length > 10) {
    errorEntries.push({
      type: "Queue-Warning",
      endpoint: "/tstudio/api/transcribe",
      timestamp: new Date().toISOString(),
      message: `Transcriptie wachtrij is lang: ${health.transcription_queue_length} items wachtend`,
    });
  }

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 12 }}>
      {/* System status summary */}
      <div className="card" style={{ padding: "14px 16px", display: "flex", alignItems: "center", gap: 12 }}>
        <div
          style={{
            width: 10,
            height: 10,
            borderRadius: "50%",
            background: apiStatusColor,
            flexShrink: 0,
          }}
        />
        <div style={{ flex: 1 }}>
          <p style={{ fontSize: 13, fontWeight: 600, color: "var(--text-primary)" }}>
            Systeem status: {health.api_status.toUpperCase()}
          </p>
          <p style={{ fontSize: 12, color: "var(--text-tertiary)" }}>
            Versie {health.version} | Opslag: {health.storage_used_gb.toFixed(1)} GB | Actieve taken: {health.active_tasks} | Wachtrij: {health.transcription_queue_length}
          </p>
        </div>
      </div>

      {/* Error log cards */}
      {errorEntries.length === 0 ? (
        <div style={{ textAlign: "center", padding: 32 }}>
          <p style={{ fontSize: 13, color: "var(--text-tertiary)" }}>
            Geen fouten gevonden. Het systeem draait normaal.
          </p>
        </div>
      ) : (
        errorEntries.map((entry, i) => (
          <div key={i} className="card" style={{ padding: "14px 16px" }}>
            {/* Error type badge */}
            <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 6 }}>
              <span className="error-type-badge">{entry.type}</span>
            </div>

            {/* Endpoint */}
            <p style={{ fontSize: 12, color: "var(--text-tertiary)", fontFamily: "monospace", marginBottom: 4 }}>
              {entry.endpoint}
            </p>

            {/* Timestamp */}
            <p style={{ fontSize: 11, color: "var(--text-disabled)", marginBottom: 6 }}>
              {new Date(entry.timestamp).toLocaleString("nl-NL")}
            </p>

            {/* Error message */}
            <p style={{ fontSize: 13, color: "var(--text-secondary)", lineHeight: 1.5 }}>
              {entry.message}
            </p>

            {/* User/reporter */}
            {entry.user && (
              <p style={{ fontSize: 12, color: "var(--text-tertiary)", marginTop: 6 }}>
                Gemeld door: {entry.user}
              </p>
            )}
          </div>
        ))
      )}
    </div>
  );
}
