import { NavLink } from "react-router-dom";
import {
  Home24Regular,
  MicRecord24Regular,
  DocumentText24Regular,
  Settings24Regular,
  ShieldPersonRegular,
} from "@fluentui/react-icons";
import { useAuthStore } from "../../stores/authStore";

export function Sidebar() {
  const user = useAuthStore((s) => s.user);
  const isAdmin = user?.role === "admin";

  return (
    <nav className="sidebar">
      {/* Main navigation */}
      <SidebarItem to="/" icon={<Home24Regular />} label="Home" />
      <SidebarItem to="/recording" icon={<MicRecord24Regular />} label="Opnemen" />
      <SidebarItem to="/transcripts" icon={<DocumentText24Regular />} label="Notulen" />

      {/* Spacer pushes bottom items down */}
      <div style={{ flex: 1 }} />

      {/* Bottom items */}
      <SidebarItem to="/settings" icon={<Settings24Regular />} label="Instellingen" />
      {isAdmin && (
        <SidebarItem to="/admin" icon={<ShieldPersonRegular />} label="Admin" />
      )}
    </nav>
  );
}

function SidebarItem({
  to,
  icon,
  label,
}: {
  to: string;
  icon: React.ReactNode;
  label: string;
}) {
  return (
    <NavLink
      to={to}
      end={to === "/"}
      className={({ isActive }) =>
        `sidebar-item${isActive ? " active" : ""}`
      }
    >
      <span className="sidebar-item-icon">{icon}</span>
      <span className="sidebar-item-label">{label}</span>
    </NavLink>
  );
}
