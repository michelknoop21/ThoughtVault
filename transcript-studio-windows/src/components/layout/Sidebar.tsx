import { NavLink } from "react-router-dom";
import {
  Home24Regular,
  MicRecord24Regular,
  DocumentText24Regular,
  Settings24Regular,
  ShieldPersonRegular,
  Person24Regular,
} from "@fluentui/react-icons";
import { useAuthStore } from "../../stores/authStore";
import appLogo from "../../assets/app-logo.png";

export function Sidebar() {
  const user = useAuthStore((s) => s.user);
  const isAdmin = user?.role === "admin";

  const userInitial = (() => {
    if (user?.name) {
      const first = user.name.trim().split(" ")[0];
      if (first) return first[0].toUpperCase();
    }
    if (user?.email) return user.email[0].toUpperCase();
    return null;
  })();

  const userDisplayName = user?.name || user?.email || "";

  return (
    <nav className="sidebar">
      {/* Logo + app title */}
      <div className="sidebar-logo-section flex-col" style={{ alignItems: "center", gap: 2 }}>
        <img
          src={appLogo}
          alt="Transcript Studio"
          className="sidebar-logo"
        />
        <span className="sidebar-developed-by">
          Prezent
        </span>
      </div>

      {/* User profile */}
      {user && (
        <div className="sidebar-user-section flex-row gap-10">
          <div className="avatar avatar-sm avatar-accent">
            {userInitial ?? <Person24Regular style={{ fontSize: 14 }} />}
          </div>
          <div className="sidebar-user-info">
            <span className="text-caption truncate" style={{ color: "var(--text-primary)", fontWeight: 500 }}>
              {userDisplayName}
            </span>
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
      <SidebarItem to="/transcripts" icon={<DocumentText24Regular />} label="Notulen" shortcut="Ctrl+3" />

      {/* Spacer pushes bottom items down */}
      <div className="flex-1" />

      <hr className="sidebar-divider" />

      {/* Bottom items */}
      <SidebarItem to="/settings" icon={<Settings24Regular />} label="Instellingen" shortcut="Ctrl+4" />
      {isAdmin && (
        <SidebarItem to="/admin" icon={<ShieldPersonRegular />} label="Beheer" />
      )}
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
