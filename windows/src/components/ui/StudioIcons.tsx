import type { SVGProps } from "react";

// Cross-platform vectors matching the symbol vocabulary and regular weight of
// the macOS app. No platform font or Windows Fluent glyph is required.
type IconProps = SVGProps<SVGSVGElement>;
const shapes = {
  house: <><path d="m3 10 9-7 9 7"/><path d="M5 9v11h5v-7h4v7h5V9"/></>,
  mic: <><rect x="9" y="3" width="6" height="12" rx="3"/><path d="M6 11v1a6 6 0 0 0 12 0v-1M12 18v3M9 21h6"/></>,
  tasks: <><rect x="5" y="4" width="14" height="17" rx="2"/><rect x="9" y="2" width="6" height="4" rx="1"/><path d="m8 10 1 1 2-2m-3 6 1 1 2-2m2-4h3m-3 5h3"/></>,
  document: <><path d="M6 3h8l4 4v14H6zM14 3v5h4M9 12h6m-6 4h6"/></>,
  people: <><circle cx="9" cy="7" r="3"/><path d="M3 20v-2a6 6 0 0 1 12 0v2M16 4a3 3 0 0 1 0 6m2 3a5 5 0 0 1 3 5v2"/></>,
  person: <><circle cx="12" cy="7" r="3.5"/><path d="M5 21v-2a7 7 0 0 1 14 0v2"/></>,
  gear: <><path d="m10 3-.5 2-2 1-2-.5-2 3 1.5 1.5v3L3.5 15l2 3 2-.5 2 1 .5 2h4l.5-2 2-1 2 .5 2-3-1.5-2v-3l1.5-1.5-2-3-2 .5-2-1L14 3z"/><circle cx="12" cy="12" r="3"/></>,
  calendar: <><rect x="3" y="5" width="18" height="16" rx="2"/><path d="M7 3v4m10-4v4M3 10h18M7 14h2m3 0h2m3 0h1M7 18h2m3 0h2"/></>,
  tray: <><path d="M4 12 2 18v3h20v-3l-2-6M2 17h6l2 3h4l2-3h6M12 2v11m-4-4 4 4 4-4"/></>,
  sliders: <><path d="M3 6h6m4 0h8M3 12h11m4 0h3M3 18h2m4 0h12"/><circle cx="11" cy="6" r="2"/><circle cx="16" cy="12" r="2"/><circle cx="7" cy="18" r="2"/></>,
  wave: <path d="M3 10v4m3-7v10m3-13v16m3-12v8m3-13v18m3-14v10m3-7v4"/>,
  search: <><circle cx="10.5" cy="10.5" r="6.5"/><path d="m16 16 5 5"/></>,
  chevronLeft: <path d="m15 5-7 7 7 7"/>, chevronRight: <path d="m9 5 7 7-7 7"/>,
  plus: <path d="M12 4v16M4 12h16"/>, cross: <path d="m5 5 14 14M19 5 5 19"/>,
  check: <path d="m4 12 5 5L20 6"/>,
  checkCircle: <><circle cx="12" cy="12" r="9"/><path d="m7 12 3 3 7-7"/></>,
  crossCircle: <><circle cx="12" cy="12" r="9"/><path d="m8 8 8 8m0-8-8 8"/></>,
  info: <><circle cx="12" cy="12" r="9"/><path d="M12 11v6m0-10v.1"/></>,
  warning: <><path d="m12 3 10 18H2zM12 9v5m0 3v.1"/></>,
  clock: <><circle cx="12" cy="12" r="9"/><path d="M12 6v6l4 2"/></>,
  pencil: <><path d="m4 16 12-12 4 4L8 20l-5 1zM14 6l4 4"/></>,
  trash: <><path d="M4 6h16M9 6V3h6v3M6 6l1 15h10l1-15M10 10v7m4-7v7"/></>,
  play: <path d="m8 4 12 8-12 8z"/>, pause: <><path d="M8 4v16m8-16v16"/></>,
  stop: <rect x="5" y="5" width="14" height="14" rx="2"/>,
  down: <path d="M12 3v12m-5-5 5 5 5-5M4 17v4h16v-4"/>,
  up: <path d="M12 16V4m-5 5 5-5 5 5M4 17v4h16v-4"/>,
  left: <path d="M21 12H3m7-7-7 7 7 7"/>, right: <path d="M3 12h18m-7-7 7 7-7 7"/>,
  refresh: <><path d="M20 9a8 8 0 0 0-14-4L3 8m0-5v5h5M4 15a8 8 0 0 0 14 4l3-3m0 5v-5h-5"/></>,
  folder: <path d="M3 6h6l2 3h10v11H3z"/>,
  tag: <><path d="M3 3h8l10 10-8 8L3 11z"/><circle cx="7" cy="7" r="1"/></>,
  more: <><circle cx="5" cy="12" r="1"/><circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/></>,
  clipboard: <><rect x="5" y="4" width="14" height="17" rx="2"/><rect x="9" y="2" width="6" height="4" rx="1"/></>,
  copy: <><rect x="8" y="8" width="13" height="13" rx="2"/><path d="M5 16H3V3h13v2"/></>,
  globe: <><circle cx="12" cy="12" r="9"/><ellipse cx="12" cy="12" rx="4" ry="9"/><path d="M3 12h18"/></>,
  server: <><rect x="3" y="3" width="18" height="7" rx="2"/><rect x="3" y="14" width="18" height="7" rx="2"/><path d="M7 6.5h.1m-.1 11h.1M12 7h5m-5 11h5"/></>,
  lock: <><rect x="5" y="10" width="14" height="11" rx="2"/><path d="M8 10V7a4 4 0 0 1 8 0v3m-4 5v2"/></>,
  key: <><circle cx="8" cy="8" r="5"/><path d="m12 12 9 9m-5-5 2-2m1 5 2-2"/></>,
  mail: <><rect x="3" y="5" width="18" height="14" rx="2"/><path d="m3 6 9 7 9-7"/></>,
  video: <><rect x="3" y="6" width="12" height="12" rx="2"/><path d="m15 10 6-4v12l-6-4"/></>,
  personAdd: <><circle cx="9" cy="7" r="3"/><path d="M3 21v-3a6 6 0 0 1 12 0v3m4-12v8m-4-4h8"/></>,
  shield: <><path d="m12 3 9 4v6c0 4-4 7-9 9-5-2-9-5-9-9V7z"/><path d="m7 12 3 3 7-7"/></>,
  star: <path d="m12 2 3 6 7 1-5 5 1 8-6-4-6 4 1-8-5-5 7-1z"/>,
  sparkle: <><path d="m12 3 2.5 6.5L21 12l-6.5 2.5L12 21l-2.5-6.5L3 12l6.5-2.5z"/><path d="M20 2v4m-2-2h4"/></>,
  laptop: <><rect x="5" y="3" width="14" height="13" rx="1"/><path d="m5 16-3 5h20l-3-5"/></>,
  code: <path d="m8 6-6 6 6 6m8-12 6 6-6 6M14 3l-4 18"/>,
  checkbox: <rect x="3" y="3" width="18" height="18" rx="3"/>,
  checkboxOn: <><rect x="3" y="3" width="18" height="18" rx="3"/><path d="m7 12 3 3 7-7"/></>,
  chat: <><path d="M3 4h15v11H9l-6 4zM18 9h3v11h-8l-4 2v-4"/><path d="M7 8h7m-7 3h5"/></>,
  send: <path d="m3 3 18 9-18 9 3-9zM6 12h15"/>,
  bug: <><ellipse cx="12" cy="14" rx="5" ry="7"/><path d="M9 8V5h6v3M3 9l4 2m10 0 4-2M2 14h5m10 0h5M3 20l4-3m10 0 4 3M12 7v14"/></>,
  share: <><path d="M12 15V3m-4 4 4-4 4 4M5 11H3v10h18V11h-2"/></>,
  signOut: <><path d="M10 3H3v18h7m0-9h11m-4-4 4 4-4 4"/></>,
};
function symbol(name: keyof typeof shapes, sfSymbol: string) {
  return function StudioIcon(props: IconProps) {
    return <svg aria-hidden="true" focusable="false" viewBox="0 0 24 24" width="1em" height="1em"
      fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"
      {...props} className={`studio-icon ${props.className || ""}`} data-symbol={sfSymbol}>{shapes[name]}</svg>;
  };
}
export const Add24Regular = symbol("plus", "plus");
export const ArrowClockwise24Regular = symbol("refresh", "refresh");
export const ArrowDownload24Regular = symbol("down", "down");
export const ArrowLeft24Regular = symbol("left", "left");
export const ArrowRight24Regular = symbol("right", "right");
export const ArrowSync16Regular = symbol("refresh", "refresh");
export const ArrowSync24Regular = symbol("refresh", "refresh");
export const ArrowUpload24Regular = symbol("up", "up");
export const BinRecycle24Regular = symbol("trash", "trash");
export const Bug24Regular = symbol("bug", "bug");
export const Calendar24Regular = symbol("calendar", "calendar");
export const CalendarLtr24Regular = symbol("calendar", "calendar");
export const ChatBubblesQuestion24Regular = symbol("chat", "chat");
export const CheckboxChecked24Regular = symbol("checkboxOn", "checkboxOn");
export const CheckboxUnchecked24Regular = symbol("checkbox", "checkbox");
export const Checkmark24Regular = symbol("check", "check");
export const CheckmarkCircle24Regular = symbol("checkCircle", "checkCircle");
export const ChevronLeft24Regular = symbol("chevronLeft", "chevronLeft");
export const ChevronRight24Regular = symbol("chevronRight", "chevronRight");
export const Clipboard24Regular = symbol("clipboard", "clipboard");
export const Clock24Regular = symbol("clock", "clock");
export const Code24Regular = symbol("code", "code");
export const Copy24Regular = symbol("copy", "copy");
export const Delete24Regular = symbol("trash", "trash");
export const Dismiss16Regular = symbol("cross", "cross");
export const Dismiss24Regular = symbol("cross", "cross");
export const DismissCircle24Regular = symbol("crossCircle", "crossCircle");
export const Document24Regular = symbol("document", "doc.text");
export const DocumentBulletList24Regular = symbol("document", "doc.text");
export const DocumentPdf24Regular = symbol("document", "doc.text");
export const DocumentText24Regular = symbol("document", "doc.text");
export const Edit24Regular = symbol("pencil", "pencil");
export const ErrorCircle24Regular = symbol("crossCircle", "crossCircle");
export const Folder24Regular = symbol("folder", "folder");
export const Globe24Regular = symbol("globe", "globe");
export const Home24Regular = symbol("house", "house");
export const Info24Regular = symbol("info", "info");
export const Key24Regular = symbol("key", "key");
export const Laptop24Regular = symbol("laptop", "laptop");
export const LockClosed24Regular = symbol("lock", "lock");
export const Mail24Regular = symbol("mail", "mail");
export const MicRecord24Regular = symbol("mic", "mic");
export const MoreHorizontal24Regular = symbol("more", "more");
export const Notebook24Regular = symbol("document", "doc.text");
export const Options24Regular = symbol("sliders", "slider.horizontal.3");
export const Pause24Regular = symbol("pause", "pause");
export const People24Regular = symbol("people", "person.2");
export const Person24Regular = symbol("person", "person");
export const PersonAdd24Regular = symbol("personAdd", "personAdd");
export const Play24Regular = symbol("play", "play");
export const Search24Regular = symbol("search", "search");
export const Send20Regular = symbol("send", "send");
export const Server24Regular = symbol("server", "server");
export const Settings24Regular = symbol("gear", "gear");
export const Share24Regular = symbol("share", "share");
export const ShieldCheckmark24Regular = symbol("shield", "shield");
export const ShieldLock24Regular = symbol("shield", "shield");
export const SignOut24Regular = symbol("signOut", "signOut");
export const Sparkle24Regular = symbol("sparkle", "sparkle");
export const Star24Regular = symbol("star", "star");
export const Stop24Regular = symbol("stop", "stop");
export const Tag24Regular = symbol("tag", "tag");
export const TaskListLtr24Regular = symbol("tasks", "list.bullet.clipboard");
export const TextDescription24Regular = symbol("document", "doc.text");
export const VideoChat24Regular = symbol("video", "video");
export const Warning24Regular = symbol("warning", "warning");
export const WaveformIcon = symbol("wave", "waveform");
export const VaultIcon = symbol("tray", "tray.and.arrow.down");
export const AdvancedIcon = symbol("sliders", "slider.horizontal.3");
