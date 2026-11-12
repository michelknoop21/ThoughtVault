import FeedbackWidget from "./components/FeedbackWidget";
import { SupportThread } from "./components/support/SupportThread";
import type { SupportTicket } from "./services/supportRelay";
import { useEffect, useState } from "react";
import { IdentityGate } from "./components/support/IdentityGate";
import { useSupportStore } from "./stores/supportStore";
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
const reviewTicket: SupportTicket = { id: "review-a", ref: "TV-2", status: "WAITING_FOR_USER", category: "BUG", description: "De notule is niet gemaakt.", createdAt: "2026-11-10T10:00:00Z", unread: true, lastMessage: { senderRole: "ADMIN", createdAt: "2026-11-10T11:00:00Z", excerpt: "Wil je het nog een keer proberen?" } };
const reviewTickets: SupportTicket[] = [reviewTicket, { id: "review-b", ref: "TV-1", status: "RESOLVED", category: "QUESTION", description: "Hoe pas ik mijn profiel aan?", createdAt: "2026-11-09T10:00:00Z", unread: false, lastMessage: null }];
const reviewMessages = [ { id: "review-1", body: "De notule is niet gemaakt.", senderRole: "USER", createdAt: "2026-11-10T10:00:00Z" }, { id: "review-2", body: "Wil je het nog een keer proberen?", senderRole: "ADMIN", createdAt: "2026-11-10T11:00:00Z" } ];
const reviewStores = new Map<number, Map<string, unknown>>();
let reviewCorrections: unknown = {version:2,dismissed:[],entries:[
 {id:"review-yinga",canonical:"Yinga",variants:["Jengo","Django"],scope:null,enabled:true,note:"Merknaam van de klant"},
 {id:"review-prezent",canonical:"Prezent",variants:[],scope:null,enabled:false}]};
const reviewContextFiles = new Map<string, string>();
Object.assign(window, { __TAURI_INTERNALS__: {
 metadata: {currentWindow:{label:"main"},currentWebview:{label:"main"}}, transformCallback: () => 0,
 invoke: async (command: string, args?: {document?:unknown;path?:string;rid?:number;key?:string;value?:unknown;name?:string;contents?:string;request?:{url:string;method:string;body?:string}}) => {
  // Fixtures run before credential or proxy fallbacks; no support request leaves this page.
  if (command === "load_credential") return "r".repeat(43);
  if (command === "store_credential" || command === "log_write") return;
  if (command === "log_tail") return "";
  if (command === "get_app_version") return "review";
  if (command === "get_system_specs") return { cpu: "Review PC", memory_gb: 16, os_version: "Windows review" };
  if (command === "proxy_request") {
    const request = args?.request;
    if (!request || !request.url.startsWith("https://thoughtvault.yinga.ai/support/")) throw new Error("Review fixture blocks proxy access");
    const path = new URL(request.url).pathname.replace("/support", "");
    const response = (data: unknown) => ({ status: 200, body: JSON.stringify(data) });
    if (path === "/installations") return response({});
    if (path === "/tickets") return response({ data: reviewTickets, pagination: {} });
    if (path === "/unread-count") return response({ data: { count: 1 } });
    if (/^\/tickets\/review-[ab]\/messages$/.test(path)) {
      if (request.method === "POST") return response({ id: "review-reply", body: JSON.parse(request.body ?? "{}").body, senderRole: "USER", createdAt: new Date().toISOString() });
      return response({ data: reviewMessages });
    }
    if (path === "/reports") return response({ ticketId: "review-a", ref: "TV-2", repeated: false, count: 1, logAttached: false });
    throw new Error("Review fixture has no matching support response");
  }
  if (command === "read_context_file") return reviewContextFiles.get(args!.name!) ?? null;
  if (command === "write_context_file") { reviewContextFiles.set(args!.name!, args!.contents!); return; }
  if (command === "plugin:store|load") {
    const rid = reviewStores.size + 1;
    reviewStores.set(rid, new Map(args?.path === "local-transcripts.json" ? [["items",useLocalTranscriptsStore.getState().items]] : []));
    return rid;
  }
  if (command === "plugin:store|get") { const store = reviewStores.get(args!.rid!); return [store?.get(args!.key!),store?.has(args!.key!) ?? false]; }
  if (command === "plugin:store|set") { reviewStores.get(args!.rid!)?.set(args!.key!,args!.value); return; }
  return command === "load_personal_corrections" ? reviewCorrections : command === "save_personal_corrections" ? (reviewCorrections = args?.document) : command === "plugin:app|name" ? "ThoughtVault" : command === "get_system_info" ? {cpu_name:"Review PC",ram_gb:16,cpu_cores:8} : [];
 },
}, __TAURI_EVENT_PLUGIN_INTERNALS__: {unregisterListener: () => {}} });
window.fetch = async () => { throw new Error("Review fixture blocks network access"); };
useSupportStore.setState({ installation_id: "11111111-1111-4111-8111-111111111111", name: "Review", email: "fake@example.com", unread_count: 1, queue: [] });
useSettingsStore.setState({processing_mode:"local",has_completed_onboarding:true});
useLocalTranscriptsStore.setState({items:Array.from({length:8}, (_, i) => ({id:`local-review-${i}`,title:["Projectoverleg","Idee voor volgende week","Voorbereiding klantgesprek"][i%3],duration_seconds:180,tags:[],created_at:new Date().toISOString(),updated_at:new Date().toISOString(),raw_transcription:"Jengo bespreekt de planning.",notule_html:"<h2>Besproken</h2><p>Jengo bespreekt de planning.</p>"}))});
usePeopleDirectoryStore.setState({people: [usePeopleDirectoryStore.getState().createDefaultPerson({name:"Voorbeeld persoon",role:"Projectleider",organization:"Voorbeeldteam",responsibilities:["Planning bewaken"]})]});
// Suggestions on the first local notule: a term, a new person and a remainder for the directory person.
reviewContextFiles.set("context-suggestions.json", JSON.stringify({"local-review-0": {
 terms:[{heard:"Kuber netes",canonical:"Kubernetes",note:"Platform voor containerbeheer"}],
 people:[{name:"Sanne Bakker",role:"Projectleider",organization:"Gemeente Utrecht",responsibilities:["Planning","Subsidieaanvraag"],topics:["Subsidie"],heardAs:["Sanne Backer"],candidateIds:[]},
  {name:"Voorbeeld persoon",role:"Teamleider",organization:"",responsibilities:[],topics:[],heardAs:["Voorbeeld P."],matchedPersonId:usePeopleDirectoryStore.getState().people[0].id,candidateIds:[]}]}}));
if (new URLSearchParams(location.search).get("scenario") === "recording") useRecordingStore.setState({phase:"recording",recordingStartedAt:Date.now()});
function IdentityReview() {
 const [ready, setReady] = useState(false);
 useEffect(() => { useSupportStore.setState({ name: "", email: "" }); setReady(true); }, []);
 return <div className="app-shell" data-theme="dark"><TitleBar/>{ready && <IdentityGate/>}</div>;
}
const pages = {"/support":<FeedbackWidget initialOpen/>,"/support-thread":<SupportThread ticket={reviewTicket} onBack={() => history.back()}/>,"/onboarding":<OnboardingWizard/>,"/seed-review":<SeedReviewSheet candidates={["voorbeeld@example.test"]} onClose={() => history.back()}/>,"/":<HomePage/>,"/recording":<RecordingPage/>,"/tasks":<TasksPage/>,"/transcripts":<TranscriptsPage/>,"/profiles":<ProfilesPage/>,"/people":<PeoplePage/>,"/settings":<SettingsPage/>};
if (new URLSearchParams(location.search).get("scenario") === "widget") {
 void import("./styles/widget.css").then(() => { const root = document.getElementById("root")!; root.id = "widget-root"; ReactDOM.createRoot(root).render(<RecordingWidget/>); });
} else ReactDOM.createRoot(document.getElementById("root")!).render(<HashRouter><Routes><Route path="/identity" element={<IdentityReview/>}/><Route path="/*" element={<div className="app-shell" data-theme="dark"><TitleBar/><div style={{flex:1,display:"flex",minHeight:0}}><Sidebar/><main className="app-main"><div className="app-main-content"><Routes>{Object.entries(pages).map(([path,element]) => <Route key={path} path={path} element={element}/>)}</Routes></div></main></div></div>}/></Routes></HashRouter>);
