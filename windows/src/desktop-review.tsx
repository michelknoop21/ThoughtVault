import { RecordingWidget } from "./components/recording/RecordingWidget";
import { OnboardingWizard } from "./components/onboarding/OnboardingWizard";
import { SeedReviewSheet } from "./pages/SeedReviewSheet";
import { usePeopleDirectoryStore } from "./stores/peopleDirectoryStore";
import { useRecordingStore } from "./stores/recordingStore";
// Development-only fixture, excluded from production Vite entrypoints.
import ReactDOM from "react-dom/client";
import { HashRouter, Routes, Route } from "react-router-dom";
import { Sidebar } from "./components/layout/Sidebar";
import { TitleBar } from "./components/layout/TitleBar";
import { HomePage } from "./pages/HomePage";
import { RecordingPage } from "./pages/RecordingPage";
import { TasksPage } from "./pages/TasksPage";
import { TranscriptsPage } from "./pages/TranscriptsPage";
import { ProfilesPage } from "./pages/ProfilesPage";
import { PeoplePage } from "./pages/PeoplePage";
import { SettingsPage } from "./pages/SettingsPage";
import { useLocalTranscriptsStore } from "./stores/localTranscriptsStore";
import { useSettingsStore } from "./stores/settingsStore";
import "./styles/globals.css";
import "./styles/thoughtvault.css";
Object.assign(window, { __TAURI_INTERNALS__: {
 metadata: {currentWindow:{label:"main"},currentWebview:{label:"main"}}, transformCallback: () => 0,
 invoke: async (command: string) => command === "plugin:app|name" ? "ThoughtVault" : command === "get_system_info" ? {cpu_name:"Review PC",ram_gb:16,cpu_cores:8} : [],
}, __TAURI_EVENT_PLUGIN_INTERNALS__: {unregisterListener: () => {}} });
window.fetch = async () => { throw new Error("Review fixture blocks network access"); };
useSettingsStore.setState({processing_mode:"local",has_completed_onboarding:true});
useLocalTranscriptsStore.setState({items:Array.from({length:8}, (_, i) => ({id:`local-review-${i}`,title:["Projectoverleg","Idee voor volgende week","Voorbereiding klantgesprek"][i%3],duration_seconds:180,tags:[],created_at:new Date().toISOString(),updated_at:new Date().toISOString(),transcription_text:"Fictieve notitie voor de layoutcontrole.",notule_html:"<h2>Besproken</h2><p>Fictieve inhoud voor de layoutcontrole.</p>"}))});
usePeopleDirectoryStore.setState({people: [usePeopleDirectoryStore.getState().createDefaultPerson({name:"Voorbeeld persoon",role:"Projectleider",organization:"Voorbeeldteam"})]});
if (new URLSearchParams(location.search).get("scenario") === "recording") useRecordingStore.setState({phase:"recording",recordingStartedAt:Date.now()});
const pages = {"/onboarding":<OnboardingWizard/>,"/seed-review":<SeedReviewSheet candidates={["voorbeeld@example.test"]} onClose={() => history.back()}/>,"/":<HomePage/>,"/recording":<RecordingPage/>,"/tasks":<TasksPage/>,"/transcripts":<TranscriptsPage/>,"/profiles":<ProfilesPage/>,"/people":<PeoplePage/>,"/settings":<SettingsPage/>};
if (new URLSearchParams(location.search).get("scenario") === "widget") {
 void import("./styles/widget.css").then(() => { const root = document.getElementById("root")!; root.id = "widget-root"; ReactDOM.createRoot(root).render(<RecordingWidget/>); });
} else ReactDOM.createRoot(document.getElementById("root")!).render(<HashRouter><div className="app-shell" data-theme="dark"><TitleBar/><div style={{flex:1,display:"flex",minHeight:0}}><Sidebar/><main className="app-main"><div className="app-main-content"><Routes>{Object.entries(pages).map(([path,element]) => <Route key={path} path={path} element={element}/>)}</Routes></div></main></div></div></HashRouter>);
