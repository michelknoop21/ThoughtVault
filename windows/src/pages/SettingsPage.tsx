import { useState } from "react";
import { Settings24Regular, Options24Regular, DocumentText24Regular, Calendar24Regular, Notebook24Regular, Person24Regular } from "@fluentui/react-icons";
import { GeneralTab } from "../components/settings/GeneralTab";
import { ProcessingTab } from "../components/settings/ProcessingTab";
import { NotulenTab } from "../components/settings/NotulenTab";
import { CalendarTab } from "../components/settings/CalendarTab";
import { ObsidianTab } from "../components/settings/ObsidianTab";
import { AccountTab } from "../components/settings/AccountTab";
import { AdvancedTab } from "../components/settings/AdvancedTab";

const TABS = [
  { name: "Algemeen", icon: <Settings24Regular /> },
  { name: "Verwerking", icon: <Options24Regular /> },
  { name: "Notulen", icon: <DocumentText24Regular /> },
  { name: "Agenda", icon: <Calendar24Regular /> },
  { name: "Obsidian", icon: <Notebook24Regular /> },
  { name: "Account", icon: <Person24Regular /> },
  { name: "Geavanceerd", icon: <Settings24Regular /> },
];

export function SettingsPage() {
  const [tab, setTab] = useState("Verwerking");

  return <div className="page-scroll northstar-settings">
    <h1>Instellingen</h1>
    <nav className="settings-tabs" aria-label="Instellingen">{TABS.map(({ name, icon }) => <button key={name} aria-current={tab === name ? "page" : undefined} className={tab === name ? "active" : ""} onClick={() => setTab(name)}>{icon}{name}</button>)}</nav>
    {tab === "Algemeen" && <GeneralTab />}
    {tab === "Verwerking" && <ProcessingTab />}
    {tab === "Notulen" && <NotulenTab />}
    {tab === "Agenda" && <CalendarTab />}
    {tab === "Obsidian" && <ObsidianTab />}
    {tab === "Account" && <AccountTab />}
    {tab === "Geavanceerd" && <AdvancedTab />}
  </div>;
}
