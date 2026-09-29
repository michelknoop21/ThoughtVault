import { NavLink } from "react-router-dom";
import {
  Home24Regular,
  MicRecord24Regular,
  TaskListLtr24Regular,
  DocumentText24Regular,
  Settings24Regular,
  ShieldPersonRegular,
  Person24Regular,
  NotepadPerson24Regular,
  PersonAccounts24Regular,
  People24Regular,
  SignOut24Regular,
} from "@fluentui/react-icons";
import { useAuthStore } from "../../stores/authStore";
import { useSettingsStore } from "../../stores/settingsStore";
import { api } from "../../services/api";
import appLogo from "../../assets/app-logo.png";

export function Sidebar() {
  const { user, logout, isAuthenticated } = useAuthStore();
  const isAdmin = user?.role === "admin";
  const processingMode = useSettingsStore((state) => state.processing_mode);

  // Display name: full name > email prefix > email
  const userDisplayName = (() => {
    if (user?.name && user.name.trim()) return user.name.trim();
    if (user?.email) return user.email.split("@")[0];
    return "Gebruiker";
  })();

  const userInitial = userDisplayName ? userDisplayName[0].toUpperCase() : null;

  async function handleLogout() {
    if (isAuthenticated) await api.logout();
    logout();
  }

  return (
    <nav className="sidebar">
      {/* Logo + app title */}
      <div className="sidebar-logo-section">
        <img
          src={appLogo}
          alt="ThoughtVault"
          className="sidebar-logo"
        />
        <span className="sidebar-app-name">ThoughtVault</span>
      </div>

      {/* User profile */}
      {user && (
        <div className="sidebar-user-section">
          <div className="avatar avatar-sm avatar-accent">
            {userInitial ?? <Person24Regular style={{ fontSize: 14 }} />}
          </div>
          <div className="sidebar-user-info">
            <span className="sidebar-user-name">{userDisplayName}</span>
            {isAdmin && (
              <span className="sidebar-role-badge">Admin</span>
            )}
          </div>
        </div>
      )}

      <hr className="sidebar-divider" />

      {/* Main navigation */}
      <SidebarItem to="/" icon={<Home24Regular />} label="Home" shortcut="Ctrl+1" />
      <SidebarItem to="/recording" icon={<MicRecord24Regular />} label="Opnemen" shortcut="Ctrl+2" />
      <SidebarItem to="/tasks" icon={<TaskListLtr24Regular />} label="Taken" />
      <SidebarItem to="/transcripts" icon={<DocumentText24Regular />} label="Notulen" shortcut="Ctrl+3" />
      {(isAuthenticated || processingMode === "local") && <SidebarItem to="/profiles" icon={<NotepadPerson24Regular />} label="Profielen" shortcut="Ctrl+5" />}
      <SidebarItem to="/people" icon={<People24Regular />} label="Mensen" shortcut="Ctrl+6" />

      {/* Spacer pushes bottom items down */}
      <div className="flex-1" />

      <hr className="sidebar-divider" />

      {/* Bottom items */}
      <SidebarItem to={isAuthenticated ? "/account" : "/login"} icon={<PersonAccounts24Regular />} label={isAuthenticated ? "Account" : "Inloggen"} />
      <SidebarItem to="/settings" icon={<Settings24Regular />} label="Instellingen" shortcut="Ctrl+4" />
      {isAdmin && (
        <SidebarItem to="/admin" icon={<ShieldPersonRegular />} label="Beheer" />
      )}

      <hr className="sidebar-divider" />

      {/* Logout button */}
      {isAuthenticated && <button
        onClick={handleLogout}
        className="sidebar-item"
        style={{ border: "none", width: "100%", textAlign: "left", cursor: "default", fontFamily: "inherit" }}
        title="Uitloggen"
      >
        <span className="sidebar-item-icon"><SignOut24Regular /></span>
        <span className="sidebar-item-label">Uitloggen</span>
      </button>}
    </nav>
  );
}

function SidebarItem({
  to,
  icon,
  label,
  shortcut,
}: {
  to: string;
  icon: React.ReactNode;
  label: string;
  shortcut?: string;
}) {
  return (
    <NavLink
      to={to}
      end={to === "/"}
      className={({ isActive }) =>
        `sidebar-item${isActive ? " active" : ""}`
      }
      title={shortcut ? `${label} (${shortcut})` : label}
    >
      <span className="sidebar-item-icon">{icon}</span>
      <span className="sidebar-item-label">{label}</span>
      {shortcut && (
        <span className="sidebar-item-shortcut">{shortcut}</span>
      )}
    </NavLink>
  );
}
