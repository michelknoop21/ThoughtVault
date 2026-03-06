import { useEffect, useState } from "react";
import {
  People24Regular,
  Bug24Regular,
  HeartPulse24Regular,
  Home24Regular,
  Mail24Regular,
  Copy24Regular,
  MoreHorizontal24Regular,
  ShieldCheckmark24Regular,
  Warning24Regular,
  ArrowRight24Regular,
  Delete24Regular,
  Key24Regular,
  LockClosed24Regular,
} from "@fluentui/react-icons";
import { api } from "../services/api";
import { useAuthStore } from "../stores/authStore";
import { useToast } from "../components/ui/InfoBar";
import type { AdminUser, AdminFeedback, SystemHealth } from "../types";

type Tab = "overview" | "users" | "invitations" | "feedback" | "health";

const TABS: { id: Tab; label: string; icon: React.ReactNode }[] = [
  { id: "overview", label: "Overzicht", icon: <Home24Regular /> },
  { id: "users", label: "Gebruikers", icon: <People24Regular /> },
  { id: "invitations", label: "Uitnodigingen", icon: <Mail24Regular /> },
  { id: "feedback", label: "Feedback", icon: <Bug24Regular /> },
  { id: "health", label: "Fouten", icon: <HeartPulse24Regular /> },
];

export function AdminPage() {
  const user = useAuthStore((s) => s.user);
  const [activeTab, setActiveTab] = useState<Tab>("overview");
  const [users, setUsers] = useState<AdminUser[]>([]);
  const [feedbackItems, setFeedbackItems] = useState<AdminFeedback[]>([]);
  const [health, setHealth] = useState<SystemHealth | null>(null);
  const [isLoading, setIsLoading] = useState(false);

  useEffect(() => {
    loadData();
  }, [activeTab]);

  async function loadData() {
    setIsLoading(true);
    try {
      if (activeTab === "overview") {
        const [usersData, feedbackData, healthData] = await Promise.all([
          api.getAdminUsers(),
          api.getFeedback(),
          api.getSystemHealth(),
        ]);
        setUsers(usersData);
        setFeedbackItems(feedbackData);
        setHealth(healthData);
      } else if (activeTab === "users") {
        const data = await api.getAdminUsers();
        setUsers(data);
      } else if (activeTab === "feedback") {
        const data = await api.getFeedback();
        setFeedbackItems(data);
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
    } catch {
      alert("Verwijderen mislukt");
    }
  }

  if (user?.role !== "admin") {
    return (
      <div className="page-scroll">
        <div className="page-content" style={{ alignItems: "center", justifyContent: "center", flex: 1 }}>
          <p className="text-secondary">Geen toegang. Alleen beheerders kunnen deze pagina bekijken.</p>
        </div>
      </div>
    );
  }

  return (
    <div className="page-scroll">
      {/* Page header */}
      <div className="page-header">
        <h1 className="page-title-sm">Beheer</h1>
      </div>

      {/* Tab bar — underline style */}
      <div className="tab-bar">
        {TABS.map((tab) => (
          <button
            key={tab.id}
            className={`tab-item${activeTab === tab.id ? " active" : ""}`}
            onClick={() => setActiveTab(tab.id)}
          >
            {tab.icon}
            {tab.label}
          </button>
        ))}
      </div>

      {/* Tab content */}
      <div className="page-content">
        {isLoading && (
          <div className="text-center text-caption" style={{ padding: 32 }}>
            Laden...
          </div>
        )}

        {!isLoading && activeTab === "overview" && (
          <OverviewTab users={users} feedbackItems={feedbackItems} health={health} />
        )}
        {!isLoading && activeTab === "users" && (
          <UsersTab users={users} onDelete={handleDeleteUser} onReload={() => loadData()} />
        )}
        {!isLoading && activeTab === "invitations" && (
          <InvitationsTab />
        )}
        {!isLoading && activeTab === "feedback" && (
          <FeedbackTab items={feedbackItems} onReload={() => loadData()} />
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
  feedbackItems,
  health,
}: {
  users: AdminUser[];
  feedbackItems: AdminFeedback[];
  health: SystemHealth | null;
}) {
  const totalTranscripts = users.reduce((sum, u) => sum + u.transcripts_count, 0);
  const totalTasks = health ? health.active_tasks + health.transcription_queue_length : 0;
  const pendingFeedback = feedbackItems.filter((f) => f.status === "new" || f.status === "open").length;

  return (
    <div className="flex-col gap-16">
      <p className="text-body-strong">Systeem statistieken</p>
      <div className="grid-2 gap-12">
        {/* Gebruikers */}
        <div className="stat-card">
          <div className="stat-card-icon stat-icon-accent">
            <People24Regular />
          </div>
          <span className="stat-card-value">{users.length}</span>
          <span className="stat-card-label">Gebruikers</span>
        </div>

        {/* Notulen */}
        <div className="stat-card">
          <div className="stat-card-icon stat-icon-success">
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
          <div className="stat-card-icon stat-icon-caution">
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <polyline points="9 11 12 14 22 4" />
              <path d="M21 12v7a2 2 0 01-2 2H5a2 2 0 01-2-2V5a2 2 0 012-2h11" />
            </svg>
          </div>
          <span className="stat-card-value">{totalTasks}</span>
          <span className="stat-card-label">Taken totaal</span>
        </div>

        {/* Open feedback */}
        <div className="stat-card">
          <div className="stat-card-icon stat-icon-critical">
            <Warning24Regular />
          </div>
          <span className="stat-card-value">{pendingFeedback}</span>
          <span className="stat-card-label">Open feedback</span>
        </div>
      </div>
    </div>
  );
}

/* ============================================================
   Gebruikers Tab
   ============================================================ */

function UsersTab({ users, onDelete, onReload }: { users: AdminUser[]; onDelete: (id: string) => void; onReload: () => void }) {
  const [showCreateForm, setShowCreateForm] = useState(false);
  const [newEmail, setNewEmail] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [newName, setNewName] = useState("");
  const [newRole, setNewRole] = useState<"user" | "admin">("user");
  const [creating, setCreating] = useState(false);
  const [menuUserId, setMenuUserId] = useState<string | null>(null);
  const [menuPos, setMenuPos] = useState<{ x: number; y: number }>({ x: 0, y: 0 });
  const [resetPasswordId, setResetPasswordId] = useState<string | null>(null);
  const [newPasswordValue, setNewPasswordValue] = useState("");
  const toast = useToast();

  useEffect(() => {
    if (!menuUserId) return;
    function close() { setMenuUserId(null); }
    document.addEventListener("click", close);
    return () => document.removeEventListener("click", close);
  }, [menuUserId]);

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
      toast.show("Gebruiker aangemaakt", "success");
      onReload();
    } catch (err) {
      toast.show("Aanmaken mislukt", "error");
    } finally {
      setCreating(false);
    }
  }

  async function handleResetPassword(userId: string) {
    if (!newPasswordValue || newPasswordValue.length < 8) {
      toast.show("Wachtwoord moet minimaal 8 tekens zijn", "error");
      return;
    }
    try {
      await api.resetUserPassword(userId, newPasswordValue);
      toast.show("Wachtwoord gereset", "success");
      setResetPasswordId(null);
      setNewPasswordValue("");
    } catch {
      toast.show("Wachtwoord resetten mislukt", "error");
    }
  }

  async function handleReset2FA(userId: string) {
    try {
      await api.resetUser2FA(userId);
      toast.show("2FA gereset", "success");
    } catch {
      toast.show("2FA resetten mislukt", "error");
    }
  }

  function openMenu(e: React.MouseEvent, userId: string) {
    e.stopPropagation();
    const rect = (e.currentTarget as HTMLElement).getBoundingClientRect();
    setMenuPos({ x: rect.right, y: rect.bottom });
    setMenuUserId(userId);
  }

  function getInitial(name: string): string {
    return name.charAt(0).toUpperCase();
  }

  return (
    <div className="flex-col gap-12">
      {/* Header with create button */}
      <div className="flex-row justify-between">
        <p className="text-caption">{users.length} gebruikers</p>
        <button
          className="btn btn-accent"
          onClick={() => setShowCreateForm(!showCreateForm)}
        >
          Gebruiker aanmaken
        </button>
      </div>

      {/* Create user form */}
      {showCreateForm && (
        <div className="card flex-col gap-10" style={{ padding: 16 }}>
          <input
            className="input"
            type="text"
            placeholder="Naam"
            value={newName}
            onChange={(e) => setNewName(e.target.value)}
          />
          <input
            className="input"
            type="email"
            placeholder="E-mail"
            value={newEmail}
            onChange={(e) => setNewEmail(e.target.value)}
          />
          <input
            className="input"
            type="password"
            placeholder="Wachtwoord"
            value={newPassword}
            onChange={(e) => setNewPassword(e.target.value)}
          />
          <select
            className="select"
            value={newRole}
            onChange={(e) => setNewRole(e.target.value as "user" | "admin")}
          >
            <option value="user">User</option>
            <option value="admin">Admin</option>
          </select>
          <div className="flex-row gap-8">
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
        <div key={user.id} className="flex-col gap-0">
          <div className="card flex-row gap-12" style={{ padding: "12px 14px" }}>
            {/* Avatar */}
            <div className="user-avatar">
              {getInitial(user.name)}
            </div>

            {/* User info */}
            <div className="flex-1">
              <div className="flex-row gap-8">
                <span className="text-body-strong">{user.name}</span>
                <span className={`role-badge ${user.role === "admin" ? "role-badge-admin" : "role-badge-user"}`}>
                  {user.role === "admin" ? "Admin" : "User"}
                </span>
                {user.role === "admin" && (
                  <ShieldCheckmark24Regular style={{ fontSize: 14, color: "var(--fill-system-success)" }} />
                )}
              </div>
              <p className="text-caption" style={{ marginTop: 2 }}>{user.email}</p>
              {user.last_login && (
                <p className="text-caption" style={{ marginTop: 1, color: "var(--text-tertiary)" }}>
                  Laatst actief: {new Date(user.last_login).toLocaleDateString("nl-NL")}
                </p>
              )}
            </div>

            {/* Action button */}
            <button
              className="icon-btn icon-btn-sm"
              onClick={(e) => openMenu(e, user.id)}
              title="Meer opties"
            >
              <MoreHorizontal24Regular />
            </button>
          </div>

          {/* Reset password inline form */}
          {resetPasswordId === user.id && (
            <div className="card card-attached flex-row gap-8">
              <input
                className="input"
                type="password"
                placeholder="Nieuw wachtwoord (min. 8 tekens)"
                value={newPasswordValue}
                onChange={(e) => setNewPasswordValue(e.target.value)}
                style={{ flex: 1 }}
                onKeyDown={(e) => { if (e.key === "Enter") handleResetPassword(user.id); }}
              />
              <button className="btn btn-accent btn-sm" onClick={() => handleResetPassword(user.id)}>
                Opslaan
              </button>
              <button className="btn btn-sm" onClick={() => { setResetPasswordId(null); setNewPasswordValue(""); }}>
                Annuleren
              </button>
            </div>
          )}
        </div>
      ))}

      {/* Context menu */}
      {menuUserId && (
        <div
          className="context-menu"
          style={{ left: menuPos.x, top: menuPos.y }}
          onClick={(e) => e.stopPropagation()}
        >
          <button
            className="context-menu-item"
            onClick={() => {
              navigator.clipboard.writeText(users.find((u) => u.id === menuUserId)?.email || "").catch(() => {});
              toast.show("E-mail gekopieerd", "success");
              setMenuUserId(null);
            }}
          >
            <Copy24Regular style={{ fontSize: 16 }} />
            Kopieer e-mail
          </button>
          <button
            className="context-menu-item"
            onClick={() => {
              setResetPasswordId(menuUserId);
              setNewPasswordValue("");
              setMenuUserId(null);
            }}
          >
            <Key24Regular style={{ fontSize: 16 }} />
            Wachtwoord resetten
          </button>
          <button
            className="context-menu-item"
            onClick={() => {
              handleReset2FA(menuUserId);
              setMenuUserId(null);
            }}
          >
            <LockClosed24Regular style={{ fontSize: 16 }} />
            2FA resetten
          </button>
          <div className="context-menu-divider" />
          <button
            className="context-menu-item context-menu-item-danger"
            onClick={() => {
              onDelete(menuUserId);
              setMenuUserId(null);
            }}
          >
            <Delete24Regular style={{ fontSize: 16 }} />
            Verwijderen
          </button>
        </div>
      )}
    </div>
  );
}

/* ============================================================
   Uitnodigingen Tab (placeholder — uses existing generateInviteCode)
   ============================================================ */

function InvitationsTab() {
  const [inviteCode, setInviteCode] = useState<string | null>(null);
  const [generating, setGenerating] = useState(false);
  const toast = useToast();

  async function handleGenerate() {
    setGenerating(true);
    try {
      const result = await api.generateInviteCode();
      setInviteCode(result.code);
      toast.show("Uitnodigingscode gegenereerd", "success");
    } catch {
      toast.show("Genereren mislukt", "error");
    } finally {
      setGenerating(false);
    }
  }

  return (
    <div className="flex-col gap-16">
      <div className="flex-row justify-between">
        <p className="text-body-strong">Uitnodigingscodes</p>
        <button className="btn btn-accent" onClick={handleGenerate} disabled={generating}>
          {generating ? "Genereren..." : "Code genereren"}
        </button>
      </div>

      {inviteCode && (
        <div className="card flex-row gap-12" style={{ padding: 16 }}>
          <code className="flex-1 invite-code">{inviteCode}</code>
          <button
            className="btn"
            onClick={() => {
              navigator.clipboard.writeText(inviteCode).catch(() => {});
              toast.show("Code gekopieerd", "success");
            }}
          >
            <Copy24Regular />
            Kopieer
          </button>
        </div>
      )}

      <p className="text-caption">
        Genereer een uitnodigingscode om nieuwe gebruikers toegang te geven tot TranscriptStudio.
      </p>
    </div>
  );
}

/* ============================================================
   Bug Rapporten Tab
   ============================================================ */

function FeedbackTab({ items, onReload }: { items: AdminFeedback[]; onReload: () => void }) {
  const toast = useToast();

  function getStatusBadgeClass(status: string): string {
    switch (status) {
      case "new": case "open": return "status-badge-new";
      case "in_progress": return "status-badge-in-progress";
      case "resolved": return "status-badge-resolved";
      case "closed": return "status-badge-closed";
      default: return "status-badge-closed";
    }
  }

  function getStatusLabel(status: string): string {
    switch (status) {
      case "new": case "open": return "Nieuw";
      case "in_progress": return "In behandeling";
      case "resolved": return "Opgelost";
      case "closed": return "Gesloten";
      default: return status;
    }
  }

  function getCategoryClass(category: string): { cls: string; label: string } {
    switch (category.toLowerCase()) {
      case "bug": return { cls: "category-bug", label: "Bug" };
      case "feature": return { cls: "category-feature", label: "Feature" };
      default: return { cls: "category-general", label: "Algemeen" };
    }
  }

  async function handleStatusChange(id: string, status: string) {
    try {
      await api.updateFeedback(id, status);
      toast.show("Status bijgewerkt", "success");
      onReload();
    } catch {
      toast.show("Status bijwerken mislukt", "error");
    }
  }

  return (
    <div className="flex-col gap-10">
      {items.length === 0 ? (
        <p className="text-caption">Geen feedback</p>
      ) : (
        items.map((item) => {
          const cat = getCategoryClass(item.category);
          return (
            <div key={item.id} className="card feedback-card">
              <div className="flex-row justify-between" style={{ marginBottom: 8 }}>
                <span className={cat.cls}>{cat.label}</span>
                <span className={getStatusBadgeClass(item.status)}>
                  {getStatusLabel(item.status)}
                </span>
              </div>

              <p className="text-body-strong" style={{ marginBottom: 4 }}>{item.title}</p>

              <p className="feedback-description">{item.description}</p>

              {item.response && (
                <p className="feedback-response">Reactie: {item.response}</p>
              )}

              <div className="flex-row justify-between">
                <div className="flex-row gap-6">
                  {(item.status === "new" || item.status === "open") && (
                    <button className="btn btn-sm" onClick={() => handleStatusChange(item.id, "in_progress")}>
                      <ArrowRight24Regular style={{ fontSize: 12 }} />
                      In behandeling
                    </button>
                  )}
                  {(item.status === "new" || item.status === "open" || item.status === "in_progress") && (
                    <button className="btn btn-sm" onClick={() => handleStatusChange(item.id, "resolved")}>
                      Opgelost
                    </button>
                  )}
                </div>
                <p className="feedback-date">
                  {new Date(item.created_at).toLocaleDateString("nl-NL", {
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
    <div className="flex-col gap-12">
      {/* System status summary */}
      <div className="card flex-row gap-12" style={{ padding: "14px 16px" }}>
        <div className="health-dot flex-shrink-0" style={{ background: apiStatusColor }} />
        <div className="flex-1">
          <p className="text-body-strong" style={{ fontSize: 13 }}>
            Systeem status: {health.api_status.toUpperCase()}
          </p>
          <p className="text-caption" style={{ overflowWrap: "anywhere" }}>
            Versie {health.version} · Opslag: {health.storage_used_gb.toFixed(1)} GB · Actieve taken: {health.active_tasks} · Wachtrij: {health.transcription_queue_length}
          </p>
        </div>
      </div>

      {/* Error log cards */}
      {errorEntries.length === 0 ? (
        <div className="empty-state">
          <p className="empty-state-text">
            Geen fouten gevonden. Het systeem draait normaal.
          </p>
        </div>
      ) : (
        errorEntries.map((entry, i) => (
          <div key={i} className="card error-card">
            {/* Error type badge */}
            <div className="flex-row gap-8" style={{ marginBottom: 6 }}>
              <span className="error-type-badge">{entry.type}</span>
            </div>

            {/* Endpoint */}
            <p className="error-endpoint">{entry.endpoint}</p>

            {/* Timestamp */}
            <p className="error-timestamp">
              {new Date(entry.timestamp).toLocaleString("nl-NL")}
            </p>

            {/* Error message */}
            <p className="error-message">{entry.message}</p>

            {/* User/reporter */}
            {entry.user && (
              <p className="error-reporter">Gemeld door: {entry.user}</p>
            )}
          </div>
        ))
      )}
    </div>
  );
}
