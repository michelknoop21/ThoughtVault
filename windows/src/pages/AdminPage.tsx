import { useEffect, useState } from "react";
import {
  People24Regular,
  Bug24Regular,
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
  Settings24Regular,
  Calendar24Regular,
  DocumentBulletList24Regular,
  Search24Regular,
  ChevronLeft24Regular,
  ChevronRight24Regular,
  Dismiss24Regular,
} from "@fluentui/react-icons";
import { api } from "../services/api";
import { useAuthStore } from "../stores/authStore";
import { useToast } from "../components/ui/InfoBar";
import { clampMenuPosition } from "../utils/menuPosition";
import type { AdminUser, AdminFeedback, SystemHealth } from "../types";

type Tab = "overview" | "users" | "invitations" | "feedback" | "health" | "settings";

const TABS: { id: Tab; label: string; icon: React.ReactNode }[] = [
  { id: "overview", label: "Overzicht", icon: <Home24Regular /> },
  { id: "users", label: "Gebruikers", icon: <People24Regular /> },
  { id: "invitations", label: "Uitnodigingen", icon: <Mail24Regular /> },
  { id: "feedback", label: "Feedback", icon: <Bug24Regular /> },
  { id: "health", label: "Logging", icon: <DocumentBulletList24Regular /> },
  { id: "settings", label: "Instellingen", icon: <Settings24Regular /> },
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
        setFeedbackItems(Array.isArray(feedbackData) ? feedbackData : []);
        setHealth(healthData);
      } else if (activeTab === "users") {
        const data = await api.getAdminUsers();
        setUsers(data);
      } else if (activeTab === "feedback") {
        const data = await api.getFeedback();
        setFeedbackItems(Array.isArray(data) ? data : []);
      } else if (activeTab === "health") {
        const [healthData, usersData] = await Promise.all([
          api.getSystemHealth(),
          api.getAdminUsers(),
        ]);
        setHealth(healthData);
        setUsers(usersData);
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
          <LoggingTab health={health} users={users} />
        )}
        {!isLoading && activeTab === "settings" && (
          <SettingsTab />
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
  const totalTranscripts = users.reduce((sum, u) => sum + (Number(u.note_count ?? u.transcripts_count) || 0), 0);
  const totalTasks = health ? (Number(health.active_tasks) || 0) + (Number(health.transcription_queue_length) || 0) : 0;
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
    const pos = clampMenuPosition(rect.right, rect.bottom);
    setMenuPos(pos);
    setMenuUserId(userId);
  }

  function getInitial(name?: string, username?: string): string {
    const val = name || username;
    if (!val) return "?";
    return String(val).charAt(0).toUpperCase();
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
            style={{ width: "100%", minWidth: 0 }}
          />
          <input
            className="input"
            type="email"
            placeholder="E-mail"
            value={newEmail}
            onChange={(e) => setNewEmail(e.target.value)}
            style={{ width: "100%", minWidth: 0 }}
          />
          <input
            className="input"
            type="password"
            placeholder="Wachtwoord"
            value={newPassword}
            onChange={(e) => setNewPassword(e.target.value)}
            style={{ width: "100%", minWidth: 0 }}
          />
          <select
            className="select"
            value={newRole}
            onChange={(e) => setNewRole(e.target.value as "user" | "admin")}
            style={{ width: "100%", minWidth: 0 }}
          >
            <option value="user">User</option>
            <option value="admin">Admin</option>
          </select>
          <div className="flex-row gap-8" style={{ flexWrap: "wrap" }}>
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
          <div className="card flex-row gap-12" style={{ padding: "12px 14px", flexWrap: "wrap" }}>
            {/* Avatar */}
            <div className="user-avatar">
              {getInitial(user.name, user.username)}
            </div>

            {/* User info */}
            <div style={{ flex: 1, minWidth: 0 }}>
              <div className="flex-row gap-8" style={{ flexWrap: "wrap" }}>
                <span className="text-body-strong">{user.name || user.username || "Onbekend"}</span>
                <span className={`role-badge ${user.role === "admin" ? "role-badge-admin" : "role-badge-user"}`}>
                  {user.role === "admin" ? "Admin" : "User"}
                </span>
                {user.role === "admin" && (
                  <ShieldCheckmark24Regular style={{ fontSize: 14, color: "var(--fill-system-success)" }} />
                )}
              </div>
              <p className="text-caption" style={{ marginTop: 2, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
                {user.email || user.username}
              </p>
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
              aria-label="Meer opties"
              title="Meer opties"
            >
              <MoreHorizontal24Regular />
            </button>
          </div>

          {/* Reset password inline form */}
          {resetPasswordId === user.id && (
            <div className="card card-attached flex-row gap-8" style={{ flexWrap: "wrap" }}>
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
              const user = users.find((u) => u.id === menuUserId);
              navigator.clipboard.writeText(user?.email || user?.username || "").catch(() => {});
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
  const [showArchived, setShowArchived] = useState(false);
  const [busyId, setBusyId] = useState<string | null>(null);

  const visibleItems = showArchived ? items : items.filter((f) => f.status !== "archived");

  function getStatusBadgeClass(status: string): string {
    switch (status) {
      case "new": case "open": return "status-badge-new";
      case "in_progress": return "status-badge-in-progress";
      case "resolved": return "status-badge-resolved";
      case "closed": return "status-badge-closed";
      case "archived": return "status-badge-closed";
      default: return "status-badge-closed";
    }
  }

  function getStatusLabel(status: string): string {
    switch (status) {
      case "new": case "open": return "Nieuw";
      case "in_progress": return "In behandeling";
      case "resolved": return "Opgelost";
      case "closed": return "Gesloten";
      case "archived": return "Gearchiveerd";
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
    if (busyId) return;
    setBusyId(id);
    try {
      await api.updateFeedback(id, status);
      toast.show("Status bijgewerkt", "success");
      onReload();
    } catch {
      toast.show("Status bijwerken mislukt", "error");
    } finally {
      setBusyId(null);
    }
  }

  async function handleDelete(id: string) {
    if (busyId) return;
    if (!confirm("Feedback definitief verwijderen?")) return;
    setBusyId(id);
    try {
      await api.deleteFeedback(id);
      toast.show("Feedback verwijderd", "success");
      onReload();
    } catch {
      toast.show("Verwijderen mislukt", "error");
    } finally {
      setBusyId(null);
    }
  }

  return (
    <div className="flex-col gap-10">
      {/* Filter toggle */}
      <div className="flex-row justify-between" style={{ alignItems: "center" }}>
        <p className="text-caption">{visibleItems.length} item{visibleItems.length !== 1 ? "s" : ""}</p>
        <label className="flex-row gap-6" style={{ alignItems: "center", cursor: "default", fontSize: 12 }}>
          <input
            type="checkbox"
            checked={showArchived}
            onChange={(e) => setShowArchived(e.target.checked)}
          />
          <span className="text-caption">Toon gearchiveerd</span>
        </label>
      </div>

      {visibleItems.length === 0 ? (
        <p className="text-caption">Geen feedback</p>
      ) : (
        visibleItems.map((item) => {
          const cat = getCategoryClass(item.category);
          const isArchived = item.status === "archived";
          return (
            <div key={item.id} className="card feedback-card" style={isArchived ? { opacity: 0.6 } : undefined}>
              <div className="flex-row justify-between" style={{ marginBottom: 8, flexWrap: "wrap", gap: 8 }}>
                <span className={cat.cls}>{cat.label}</span>
                <span className={getStatusBadgeClass(item.status)}>
                  {getStatusLabel(item.status)}
                </span>
              </div>

              <p className="text-body-strong" style={{ marginBottom: 4 }}>{item.title}</p>

              <p className="feedback-description">{item.description}</p>

              {(item.response || item.admin_response) && (
                <p className="feedback-response">Reactie: {item.response ?? item.admin_response}</p>
              )}

              <div className="flex-row justify-between" style={{ flexWrap: "wrap", gap: 8 }}>
                <div className="flex-row gap-6" style={{ flexWrap: "wrap" }}>
                  {isArchived ? (
                    <button className="btn btn-sm" disabled={busyId === item.id} onClick={() => handleStatusChange(item.id, "open")}>
                      Herstellen
                    </button>
                  ) : (
                    <>
                      {(item.status === "new" || item.status === "open") && (
                        <button className="btn btn-sm" disabled={busyId === item.id} onClick={() => handleStatusChange(item.id, "in_progress")}>
                          <ArrowRight24Regular style={{ fontSize: 12 }} />
                          In behandeling
                        </button>
                      )}
                      {(item.status === "new" || item.status === "open" || item.status === "in_progress") && (
                        <button className="btn btn-sm" disabled={busyId === item.id} onClick={() => handleStatusChange(item.id, "resolved")}>
                          Opgelost
                        </button>
                      )}
                      <button className="btn btn-sm" disabled={busyId === item.id} onClick={() => handleStatusChange(item.id, "archived")}>
                        Archiveren
                      </button>
                    </>
                  )}
                  <button
                    className="btn btn-sm"
                    disabled={busyId === item.id}
                    style={{ color: "var(--text-error)" }}
                    onClick={() => handleDelete(item.id)}
                  >
                    <Delete24Regular style={{ fontSize: 12 }} />
                    Verwijderen
                  </button>
                </div>
                <p className="feedback-date">
                  {item.created_at ? new Date(item.created_at).toLocaleDateString("nl-NL", {
                    day: "numeric",
                    month: "short",
                    year: "numeric",
                  }) : "-"}
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
   Logging Tab — Activity + Errors with filters & pagination
   ============================================================ */

type LogSubTab = "activity" | "errors";

const PAGE_SIZE = 25;

function LoggingTab({ health, users }: { health: SystemHealth; users: AdminUser[] }) {
  const [subTab, setSubTab] = useState<LogSubTab>("activity");
  const [activityLogs, setActivityLogs] = useState<Record<string, unknown>[]>([]);
  const [errorLogs, setErrorLogs] = useState<Record<string, unknown>[]>([]);
  const [isLoadingLogs, setIsLoadingLogs] = useState(false);
  const [expandedRow, setExpandedRow] = useState<number | null>(null);

  // Filters
  const [filterUser, setFilterUser] = useState("");
  const [filterType, setFilterType] = useState(""); // action_type for activity, severity for errors
  const [filterSearch, setFilterSearch] = useState("");
  const [filterDateFrom, setFilterDateFrom] = useState("");
  const [filterDateTo, setFilterDateTo] = useState("");

  // Pagination
  const [page, setPage] = useState(1);

  // Load logs when sub-tab or filters change
  useEffect(() => {
    loadLogs();
    setPage(1);
    setExpandedRow(null);
  }, [subTab, filterUser, filterType, filterDateFrom, filterDateTo]);

  // Debounced search
  useEffect(() => {
    const timer = setTimeout(() => {
      loadLogs();
      setPage(1);
      setExpandedRow(null);
    }, 300);
    return () => clearTimeout(timer);
  }, [filterSearch]);

  async function loadLogs() {
    setIsLoadingLogs(true);
    try {
      if (subTab === "activity") {
        const data = await api.getAdminActivity({
          limit: 500,
          user_id: filterUser || undefined,
          action_type: filterType || undefined,
          search: filterSearch || undefined,
          start_date: filterDateFrom || undefined,
          end_date: filterDateTo || undefined,
        });
        setActivityLogs(data as Record<string, unknown>[]);
      } else {
        const data = await api.getAdminErrors({
          limit: 500,
          severity: filterType || undefined,
          user_id: filterUser || undefined,
          search: filterSearch || undefined,
          start_date: filterDateFrom || undefined,
          end_date: filterDateTo || undefined,
        });
        setErrorLogs(data as Record<string, unknown>[]);
      }
    } catch {
      // Silently handle — empty state will show
    } finally {
      setIsLoadingLogs(false);
    }
  }

  function clearFilters() {
    setFilterUser("");
    setFilterType("");
    setFilterSearch("");
    setFilterDateFrom("");
    setFilterDateTo("");
  }

  const hasFilters = filterUser || filterType || filterSearch || filterDateFrom || filterDateTo;

  // Current data & pagination
  const currentData = subTab === "activity" ? activityLogs : errorLogs;
  const totalItems = currentData.length;
  const totalPages = Math.max(1, Math.ceil(totalItems / PAGE_SIZE));
  const safePage = Math.min(page, totalPages);
  const startIdx = (safePage - 1) * PAGE_SIZE;
  const pageData = currentData.slice(startIdx, startIdx + PAGE_SIZE);

  // System status
  const apiStatus = health.api_status || "unknown";
  const apiStatusColor =
    apiStatus === "ok" ? "var(--fill-system-success)"
    : apiStatus === "degraded" ? "var(--fill-system-caution)"
    : "var(--fill-system-critical)";

  // Extract unique action types from activity logs for filter dropdown
  const activityActionTypes = [...new Set(activityLogs.map(
    (e) => String(e.action_type ?? e.action ?? e.event ?? "")
  ).filter(Boolean))].sort();

  return (
    <div className="flex-col gap-12">
      {/* Compact system status banner */}
      <div className="card flex-row gap-10" style={{ padding: "10px 14px", alignItems: "center" }}>
        <div className="health-dot flex-shrink-0" style={{ background: apiStatusColor }} />
        <span className="text-caption" style={{ flex: 1, overflowWrap: "anywhere" }}>
          <strong>Status: {apiStatus.toUpperCase()}</strong>
          {health.model ? ` · ${health.model}` : ""}
          {health.device ? ` · ${health.device.toUpperCase()}` : ""}
          {` · Taken: ${health.active_tasks ?? 0}`}
          {` · Wachtrij: ${health.transcription_queue_length ?? 0}`}
        </span>
      </div>

      {/* Sub-tab toggle */}
      <div className="log-sub-tabs">
        <button
          className={`log-sub-tab${subTab === "activity" ? " active" : ""}`}
          onClick={() => { setSubTab("activity"); clearFilters(); }}
        >
          Activiteit
          <span className="log-sub-tab-count">{subTab === "activity" ? totalItems : ""}</span>
        </button>
        <button
          className={`log-sub-tab${subTab === "errors" ? " active" : ""}`}
          onClick={() => { setSubTab("errors"); clearFilters(); }}
        >
          Fouten
          <span className="log-sub-tab-count">{subTab === "errors" ? totalItems : ""}</span>
        </button>
      </div>

      {/* Filter bar */}
      <div className="log-filter-bar">
        <div className="log-filter-search">
          <Search24Regular style={{ fontSize: 14, color: "var(--text-tertiary)", flexShrink: 0 }} />
          <input
            className="log-filter-search-input"
            type="text"
            placeholder={subTab === "activity" ? "Zoek op gebruiker, actie, endpoint..." : "Zoek op foutmelding, endpoint, type..."}
            value={filterSearch}
            onChange={(e) => setFilterSearch(e.target.value)}
          />
          {filterSearch && (
            <button className="log-filter-clear-btn" onClick={() => setFilterSearch("")}>
              <Dismiss24Regular style={{ fontSize: 12 }} />
            </button>
          )}
        </div>

        <select
          className="log-filter-select"
          value={filterUser}
          onChange={(e) => setFilterUser(e.target.value)}
        >
          <option value="">Alle gebruikers</option>
          {users.map((u) => (
            <option key={u.id} value={u.id}>{u.name || u.username}</option>
          ))}
        </select>

        {subTab === "activity" ? (
          <select
            className="log-filter-select"
            value={filterType}
            onChange={(e) => setFilterType(e.target.value)}
          >
            <option value="">Alle acties</option>
            {activityActionTypes.map((t) => (
              <option key={t} value={t}>{t}</option>
            ))}
          </select>
        ) : (
          <select
            className="log-filter-select"
            value={filterType}
            onChange={(e) => setFilterType(e.target.value)}
          >
            <option value="">Alle niveaus</option>
            <option value="error">Error</option>
            <option value="warning">Warning</option>
            <option value="info">Info</option>
          </select>
        )}

        <input
          className="log-filter-date"
          type="date"
          value={filterDateFrom}
          onChange={(e) => setFilterDateFrom(e.target.value)}
          title="Vanaf datum"
        />
        <input
          className="log-filter-date"
          type="date"
          value={filterDateTo}
          onChange={(e) => setFilterDateTo(e.target.value)}
          title="Tot datum"
        />

        {hasFilters && (
          <button className="btn btn-sm" onClick={clearFilters} title="Filters wissen">
            <Dismiss24Regular style={{ fontSize: 12 }} />
            Wis filters
          </button>
        )}
      </div>

      {/* Log table */}
      {isLoadingLogs ? (
        <div className="text-center text-caption" style={{ padding: 32 }}>Laden...</div>
      ) : pageData.length === 0 ? (
        <div className="empty-state">
          <p className="empty-state-text">
            {hasFilters
              ? "Geen resultaten voor deze filters."
              : subTab === "activity"
              ? "Geen activiteit gevonden."
              : "Geen fouten gevonden. Het systeem draait normaal."}
          </p>
        </div>
      ) : subTab === "activity" ? (
        <ActivityLogTable
          entries={pageData}
          expandedRow={expandedRow}
          onToggleRow={(i) => setExpandedRow(expandedRow === i ? null : i)}
          startIdx={startIdx}
        />
      ) : (
        <ErrorLogTable
          entries={pageData}
          expandedRow={expandedRow}
          onToggleRow={(i) => setExpandedRow(expandedRow === i ? null : i)}
          startIdx={startIdx}
        />
      )}

      {/* Pagination */}
      {totalPages > 1 && (
        <div className="log-pagination">
          <span className="text-caption">
            {startIdx + 1}–{Math.min(startIdx + PAGE_SIZE, totalItems)} van {totalItems}
          </span>
          <div className="log-pagination-controls">
            <button
              className="icon-btn icon-btn-sm"
              disabled={safePage <= 1}
              onClick={() => setPage(safePage - 1)}
              title="Vorige pagina"
            >
              <ChevronLeft24Regular />
            </button>
            {generatePageNumbers(safePage, totalPages).map((p, i) =>
              p === "..." ? (
                <span key={`dots-${i}`} className="log-pagination-dots">...</span>
              ) : (
                <button
                  key={p}
                  className={`log-pagination-page${safePage === p ? " active" : ""}`}
                  onClick={() => setPage(p as number)}
                >
                  {p}
                </button>
              )
            )}
            <button
              className="icon-btn icon-btn-sm"
              disabled={safePage >= totalPages}
              onClick={() => setPage(safePage + 1)}
              title="Volgende pagina"
            >
              <ChevronRight24Regular />
            </button>
          </div>
        </div>
      )}
    </div>
  );
}

/** Generate smart page number list: [1, 2, ..., 5, 6, 7, ..., 20] */
function generatePageNumbers(current: number, total: number): (number | "...")[] {
  if (total <= 7) return Array.from({ length: total }, (_, i) => i + 1);
  const pages: (number | "...")[] = [];
  pages.push(1);
  if (current > 3) pages.push("...");
  for (let i = Math.max(2, current - 1); i <= Math.min(total - 1, current + 1); i++) {
    pages.push(i);
  }
  if (current < total - 2) pages.push("...");
  pages.push(total);
  return pages;
}

function formatLogTimestamp(ts: string): string {
  if (!ts) return "-";
  const d = new Date(ts);
  const now = new Date();
  const isToday = d.toDateString() === now.toDateString();
  const yesterday = new Date(now);
  yesterday.setDate(yesterday.getDate() - 1);
  const isYesterday = d.toDateString() === yesterday.toDateString();

  const time = d.toLocaleTimeString("nl-NL", { hour: "2-digit", minute: "2-digit" });
  if (isToday) return `Vandaag ${time}`;
  if (isYesterday) return `Gisteren ${time}`;
  return d.toLocaleDateString("nl-NL", { day: "numeric", month: "short" }) + ` ${time}`;
}

function getActionLabel(action: string): string {
  const labels: Record<string, string> = {
    login: "Ingelogd",
    logout: "Uitgelogd",
    upload: "Upload",
    transcribe: "Transcriptie",
    task_created: "Taak aangemaakt",
    task_deleted: "Taak verwijderd",
    task_completed: "Taak voltooid",
    note_generated: "Notulen gegenereerd",
    note_deleted: "Notulen verwijderd",
    profile_created: "Profiel aangemaakt",
    profile_updated: "Profiel bijgewerkt",
    user_created: "Gebruiker aangemaakt",
    user_deleted: "Gebruiker verwijderd",
    password_reset: "Wachtwoord gereset",
    settings_updated: "Instellingen bijgewerkt",
    feedback_submitted: "Feedback ingediend",
  };
  return labels[action.toLowerCase()] ?? action;
}

function getActionBadgeClass(action: string): string {
  const a = action.toLowerCase();
  if (a.includes("login") || a.includes("logout")) return "log-badge-auth";
  if (a.includes("upload") || a.includes("transcrib")) return "log-badge-upload";
  if (a.includes("delet")) return "log-badge-danger";
  if (a.includes("creat") || a.includes("generat")) return "log-badge-success";
  return "log-badge-default";
}

function ActivityLogTable({
  entries,
  expandedRow,
  onToggleRow,
  startIdx,
}: {
  entries: Record<string, unknown>[];
  expandedRow: number | null;
  onToggleRow: (i: number) => void;
  startIdx: number;
}) {
  return (
    <div className="log-table-wrapper">
      <table className="log-table">
        <thead>
          <tr>
            <th style={{ width: 140 }}>Tijd</th>
            <th style={{ width: 160 }}>Gebruiker</th>
            <th style={{ width: 140 }}>Actie</th>
            <th>Endpoint</th>
          </tr>
        </thead>
        <tbody>
          {entries.map((entry, i) => {
            const globalIdx = startIdx + i;
            const user = String(entry.username ?? entry.user ?? entry.user_email ?? "");
            const action = String(entry.action_type ?? entry.action ?? entry.event ?? "");
            const endpoint = String(entry.endpoint ?? entry.path ?? entry.url ?? "");
            const timestamp = String(entry.timestamp ?? entry.created_at ?? entry.date ?? "");
            const details = String(entry.details ?? entry.detail ?? entry.description ?? entry.message ?? "");
            const ip = String(entry.ip_address ?? entry.ip ?? "");
            const isExpanded = expandedRow === globalIdx;

            return (
              <tr
                key={globalIdx}
                className={`log-table-row${isExpanded ? " expanded" : ""}`}
                onClick={() => onToggleRow(globalIdx)}
              >
                <td className="log-table-time">{formatLogTimestamp(timestamp)}</td>
                <td className="log-table-user" title={user}>{user || "-"}</td>
                <td>
                  <span className={`log-badge ${getActionBadgeClass(action)}`}>
                    {getActionLabel(action)}
                  </span>
                </td>
                <td className="log-table-endpoint">
                  <span className="log-endpoint-text">{endpoint || "-"}</span>
                  {isExpanded && (details || ip) && (
                    <div className="log-expanded-details">
                      {details && details !== "undefined" && (
                        <p className="log-detail-line"><span className="log-detail-label">Details:</span> {details}</p>
                      )}
                      {ip && ip !== "undefined" && (
                        <p className="log-detail-line"><span className="log-detail-label">IP:</span> {ip}</p>
                      )}
                    </div>
                  )}
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}

function ErrorLogTable({
  entries,
  expandedRow,
  onToggleRow,
  startIdx,
}: {
  entries: Record<string, unknown>[];
  expandedRow: number | null;
  onToggleRow: (i: number) => void;
  startIdx: number;
}) {
  function severityColor(severity: string): string {
    switch (severity.toLowerCase()) {
      case "error": case "critical": return "var(--fill-system-critical)";
      case "warning": return "var(--fill-system-caution)";
      case "info": return "var(--fill-brand-primary)";
      default: return "var(--fill-system-critical)";
    }
  }

  return (
    <div className="log-table-wrapper">
      <table className="log-table">
        <thead>
          <tr>
            <th style={{ width: 140 }}>Tijd</th>
            <th style={{ width: 80 }}>Ernst</th>
            <th style={{ width: 130 }}>Type</th>
            <th style={{ width: 200 }}>Endpoint</th>
            <th>Foutmelding</th>
          </tr>
        </thead>
        <tbody>
          {entries.map((entry, i) => {
            const globalIdx = startIdx + i;
            const type = String(entry.type ?? entry.error_type ?? entry.level ?? "error");
            const severity = String(entry.severity ?? entry.level ?? entry.type ?? entry.error_type ?? "error");
            const message = String(entry.message ?? entry.error ?? entry.error_message ?? entry.detail ?? "Onbekende fout");
            const timestamp = String(entry.timestamp ?? entry.created_at ?? entry.date ?? "");
            const endpoint = String(entry.endpoint ?? entry.path ?? entry.url ?? "");
            const user = String(entry.user ?? entry.username ?? entry.user_id ?? "");
            const stackTrace = String(entry.stack_trace ?? entry.traceback ?? entry.stacktrace ?? "");
            const sevColor = severityColor(severity);
            const isExpanded = expandedRow === globalIdx;

            return (
              <tr
                key={globalIdx}
                className={`log-table-row${isExpanded ? " expanded" : ""}`}
                onClick={() => onToggleRow(globalIdx)}
                style={{ borderLeft: `3px solid ${sevColor}` }}
              >
                <td className="log-table-time">{formatLogTimestamp(timestamp)}</td>
                <td>
                  <span
                    className="error-type-badge"
                    style={{
                      background: `color-mix(in srgb, ${sevColor} 15%, transparent)`,
                      color: sevColor,
                    }}
                  >
                    {severity}
                  </span>
                </td>
                <td className="log-table-type">{type}</td>
                <td className="log-table-endpoint">
                  <span className="log-endpoint-text">{endpoint || "-"}</span>
                </td>
                <td className="log-table-message">
                  <span className="log-message-text">{message}</span>
                  {isExpanded && (
                    <div className="log-expanded-details">
                      {user && user !== "undefined" && (
                        <p className="log-detail-line"><span className="log-detail-label">Gebruiker:</span> {user}</p>
                      )}
                      {stackTrace && stackTrace !== "undefined" && (
                        <pre className="log-stacktrace">{stackTrace}</pre>
                      )}
                    </div>
                  )}
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}

/* ============================================================
   Instellingen Tab (Microsoft 365 OAuth)
   ============================================================ */

function SettingsTab() {
  const [ms365ClientId, setMs365ClientId] = useState("");
  const [ms365TenantId, setMs365TenantId] = useState("");
  const [googleOAuthClientIdMacos, setGoogleOAuthClientIdMacos] = useState("");
  const [googleOAuthClientIdWindows, setGoogleOAuthClientIdWindows] = useState("");
  const [youtubeMaxDurationMinutes, setYoutubeMaxDurationMinutes] = useState("120");
  const [youtubeExtractorArgs, setYoutubeExtractorArgs] = useState("youtube:player_client=web;fetch_pot=always");
  const [youtubeCookiesContent, setYoutubeCookiesContent] = useState("");
  const [isLoading, setIsLoading] = useState(false);
  const [showSaved, setShowSaved] = useState(false);
  const toast = useToast();

  useEffect(() => {
    loadSettings();
  }, []);

  async function loadSettings() {
    try {
      const settings = await api.getAdminSettings();
      setMs365ClientId(settings.ms365_client_id ?? "");
      setMs365TenantId(settings.ms365_tenant_id ?? "");
      setGoogleOAuthClientIdMacos(settings.google_oauth_client_id_macos ?? "");
      setGoogleOAuthClientIdWindows(settings.google_oauth_client_id_windows ?? "");
      setYoutubeMaxDurationMinutes(String(settings.youtube_max_duration_minutes ?? 120));
      setYoutubeExtractorArgs(settings.youtube_extractor_args ?? "youtube:player_client=web;fetch_pot=always");
      setYoutubeCookiesContent(settings.youtube_cookies_content ?? "");
    } catch (err) {
      console.error("Settings load failed:", err);
    }
  }

  async function handleSave() {
    setIsLoading(true);
    setShowSaved(false);
    try {
      await api.updateAdminSettings({
        ms365_client_id: ms365ClientId || undefined,
        ms365_tenant_id: ms365TenantId || undefined,
        google_oauth_client_id_macos: googleOAuthClientIdMacos || undefined,
        google_oauth_client_id_windows: googleOAuthClientIdWindows || undefined,
        youtube_max_duration_minutes: youtubeMaxDurationMinutes ? Number(youtubeMaxDurationMinutes) : undefined,
        youtube_extractor_args: youtubeExtractorArgs || undefined,
        youtube_cookies_content: youtubeCookiesContent,
      });
      setShowSaved(true);
      setTimeout(() => setShowSaved(false), 3000);
      toast.show("Instellingen opgeslagen", "success");
    } catch {
      toast.show("Opslaan mislukt", "error");
    } finally {
      setIsLoading(false);
    }
  }

  return (
    <div className="flex-col gap-16">
      {/* Microsoft 365 OAuth Section */}
      <div className="card flex-col gap-12" style={{ padding: 16 }}>
        <div className="flex-row gap-8">
          <Calendar24Regular style={{ fontSize: 20, color: "var(--fill-brand-primary)" }} />
          <p className="text-body-strong">Microsoft 365 Agenda</p>
        </div>

        <p className="text-caption" style={{ color: "var(--text-secondary)" }}>
          Configureer OAuth credentials zodat gebruikers hun Microsoft 365 agenda kunnen koppelen.
          Maak een App Registration aan in Azure Portal met redirect URI: <code>transcript-studio://auth/callback</code>
        </p>

        {/* Client ID */}
        <div className="flex-col gap-4">
          <label className="form-label">Client ID</label>
          <input
            className="input"
            type="text"
            placeholder="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
            value={ms365ClientId}
            onChange={(e) => setMs365ClientId(e.target.value)}
            style={{ fontFamily: "monospace" }}
          />
        </div>

        {/* Tenant ID */}
        <div className="flex-col gap-4">
          <label className="form-label">Tenant ID</label>
          <input
            className="input"
            type="text"
            placeholder="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
            value={ms365TenantId}
            onChange={(e) => setMs365TenantId(e.target.value)}
            style={{ fontFamily: "monospace" }}
          />
        </div>
      </div>

      {/* Google OAuth Section */}
      <div className="card flex-col gap-12" style={{ padding: 16 }}>
        <div className="flex-row gap-8">
          <ShieldCheckmark24Regular style={{ fontSize: 20, color: "var(--fill-brand-primary)" }} />
          <p className="text-body-strong">Google OAuth (YouTube)</p>
        </div>

        <p className="text-caption" style={{ color: "var(--text-secondary)" }}>
          Configureer Google OAuth credentials zodat gebruikers YouTube video's kunnen transcriberen via de Captions API.
          Maak een OAuth Client ID aan in Google Cloud Console met redirect URI: <code>transcript-studio://google/callback</code>
        </p>

        <div className="flex-col gap-4">
          <label className="form-label">Client ID (macOS)</label>
          <input
            className="input"
            type="text"
            placeholder="xxxxxxxx.apps.googleusercontent.com"
            value={googleOAuthClientIdMacos}
            onChange={(e) => setGoogleOAuthClientIdMacos(e.target.value)}
            style={{ fontFamily: "monospace" }}
          />
        </div>

        <div className="flex-col gap-4">
          <label className="form-label">Client ID (Windows)</label>
          <input
            className="input"
            type="text"
            placeholder="xxxxxxxx.apps.googleusercontent.com"
            value={googleOAuthClientIdWindows}
            onChange={(e) => setGoogleOAuthClientIdWindows(e.target.value)}
            style={{ fontFamily: "monospace" }}
          />
        </div>
      </div>

      {/* YouTube Settings Section */}
      <div className="card flex-col gap-12" style={{ padding: 16 }}>
        <div className="flex-row gap-8">
          <Warning24Regular style={{ fontSize: 20, color: "#ff0000" }} />
          <p className="text-body-strong">YouTube Instellingen</p>
        </div>

        <p className="text-caption" style={{ color: "var(--text-secondary)" }}>
          Configureer hoe yt-dlp YouTube video's downloadt. Standaard wordt de web client gebruikt met PO token authenticatie.
        </p>

        <div className="flex-col gap-4">
          <label className="form-label">Maximale videoduur (minuten)</label>
          <input
            className="input"
            type="number"
            placeholder="120"
            value={youtubeMaxDurationMinutes}
            onChange={(e) => setYoutubeMaxDurationMinutes(e.target.value)}
            style={{ width: 120 }}
          />
        </div>

        <div className="flex-col gap-4">
          <label className="form-label">yt-dlp Extractor Args</label>
          <input
            className="input"
            type="text"
            placeholder="youtube:player_client=web;fetch_pot=always"
            value={youtubeExtractorArgs}
            onChange={(e) => setYoutubeExtractorArgs(e.target.value)}
            style={{ fontFamily: "monospace" }}
          />
        </div>

        <div className="flex-col gap-4">
          <label className="form-label">Cookies (optioneel)</label>
          <p className="text-caption" style={{ color: "var(--text-tertiary)", marginTop: -4 }}>
            Plak Netscape-formaat cookies voor video's die anoniem niet beschikbaar zijn.
          </p>
          <textarea
            className="input"
            placeholder="# Netscape HTTP Cookie File&#10;.youtube.com&#9;TRUE&#9;/&#9;..."
            value={youtubeCookiesContent}
            onChange={(e) => setYoutubeCookiesContent(e.target.value)}
            rows={4}
            style={{ fontFamily: "monospace", resize: "vertical" }}
          />
        </div>
      </div>

      {/* Actions */}
      <div className="flex-row gap-8">
        <button
          className="btn btn-accent"
          onClick={handleSave}
          disabled={isLoading}
        >
          {isLoading ? "Opslaan..." : "Opslaan"}
        </button>

        {showSaved && (
          <div className="flex-row gap-6" style={{ color: "var(--fill-system-success)" }}>
            <span style={{ fontSize: 14 }}>✓</span>
            <span className="text-caption">Opgeslagen</span>
          </div>
        )}
      </div>
    </div>
  );
}
