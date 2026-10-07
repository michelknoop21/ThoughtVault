import { NavLink } from "react-router-dom";
import {
  Home24Regular,
  MicRecord24Regular,
  TaskListLtr24Regular,
  DocumentText24Regular,
  Settings24Regular,
  NotepadPerson24Regular,
  People24Regular,
} from "@fluentui/react-icons";
import appLogo from "../../assets/app-logo.png";

export function Sidebar() {
  return (
    <nav className="sidebar" aria-label="Hoofdnavigatie" data-theme="dark">
      {/* Logo + app title */}
      <div className="sidebar-logo-section">
        <img
          src={appLogo}
          alt="ThoughtVault"
          className="sidebar-logo"
        />
        <span className="sidebar-app-name">ThoughtVault</span>
      </div>

      <hr className="sidebar-divider" />

      {/* Main navigation */}
      <SidebarItem to="/" icon={<Home24Regular />} label="Home" shortcut="Ctrl+1" />
      <SidebarItem to="/recording" icon={<MicRecord24Regular />} label="Opnemen" shortcut="Ctrl+2" />
      <SidebarItem to="/tasks" icon={<TaskListLtr24Regular />} label="Taken" />
      <SidebarItem to="/transcripts" icon={<DocumentText24Regular />} label="Notulen" shortcut="Ctrl+3" />
      <SidebarItem to="/profiles" icon={<NotepadPerson24Regular />} label="Profielen" shortcut="Ctrl+5" />
      <SidebarItem to="/people" icon={<People24Regular />} label="Mensen" shortcut="Ctrl+6" />

      {/* Spacer pushes bottom items down */}
      <div className="flex-1" />

      <hr className="sidebar-divider" />

      {/* Bottom items */}
      <SidebarItem to="/settings" icon={<Settings24Regular />} label="Instellingen" shortcut="Ctrl+4" />
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
