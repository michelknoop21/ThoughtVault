import { useEffect, useState } from "react";
import { BrandFooter } from "../brand/BrandFooter";
import { NavLink, useLocation, useNavigate } from "react-router-dom";
import {
  Home24Regular,
  MicRecord24Regular,
  TaskListLtr24Regular,
  DocumentText24Regular,
  Settings24Regular,
  ChevronLeft24Regular,
  ChevronRight24Regular,
  People24Regular,
} from "../ui/StudioIcons";
import { useLocalTranscriptsStore } from "../../stores/localTranscriptsStore";
import { useTranscriptsStore } from "../../stores/transcriptsStore";
import appLogo from "../../assets/app-logo.png";

export function Sidebar() {
  const [collapsed, setCollapsed] = useState(false);
  useEffect(() => {
    const toggle = (event: KeyboardEvent) => {
      if (event.ctrlKey && event.shiftKey && event.key.toLowerCase() === "s") {
        event.preventDefault();
        setCollapsed(value => !value);
      }
    };
    window.addEventListener("keydown", toggle);
    return () => window.removeEventListener("keydown", toggle);
  }, []);
  const location = useLocation();
  const navigate = useNavigate();
  const local = useLocalTranscriptsStore(s => s.items);
  const remote = useTranscriptsStore(s => s.transcripts);
  const select = useTranscriptsStore(s => s.setSelectedId);
  const recent = [...new Map([...remote, ...local].map(t => [t.id, t])).values()]
    .sort((a, b) => Date.parse(b.created_at) - Date.parse(a.created_at)).slice(0, 5);
  return (
    <nav className={`sidebar${collapsed ? " collapsed" : ""}`} aria-label="Hoofdnavigatie" data-theme="dark">
      <button type="button" className="sidebar-toggle" aria-label={collapsed ? "Zijbalk uitklappen" : "Zijbalk inklappen"} aria-expanded={!collapsed} onClick={() => setCollapsed(!collapsed)}>{collapsed ? <ChevronRight24Regular /> : <ChevronLeft24Regular />}</button>
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
      <SidebarItem to="/tasks" icon={<TaskListLtr24Regular />} label="Taken" shortcut="Ctrl+3" />
      <SidebarItem to="/transcripts" icon={<DocumentText24Regular />} label="Notulen" shortcut="Ctrl+4" />
      <SidebarItem to="/people" icon={<People24Regular />} label="Mensen" shortcut="Ctrl+5" />

      {!collapsed && location.pathname !== "/" && recent.length > 0 && <section className="sidebar-recent" aria-label="Recente notulen">
        <h2>Recent</h2>
        {recent.map(t => <button key={t.id} onClick={() => { select(t.id); navigate("/transcripts"); }} title={t.title}>
          <span className="sidebar-recent-icon"><DocumentText24Regular /></span>
          <span>{t.title || "Naamloze opname"}</span>
        </button>)}
      </section>}
      {/* Spacer pushes bottom items down */}
      <div className="flex-1" />

      <hr className="sidebar-divider" />

      {/* Bottom items */}
      <SidebarItem to="/settings" icon={<Settings24Regular />} label="Instellingen" shortcut="Ctrl+6" />
      {!collapsed && <BrandFooter compact />}
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
