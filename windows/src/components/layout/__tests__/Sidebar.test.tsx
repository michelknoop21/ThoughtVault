import { act } from "react";
import { createRoot } from "react-dom/client";
import { MemoryRouter } from "react-router-dom";
import { expect, it } from "vitest";
import { Sidebar } from "../Sidebar";
it("toggles desktop navigation with Ctrl+Shift+S, keeping every destination", async () => {
 const host = document.createElement("div"), root = createRoot(host);
 await act(async () => {root.render(<MemoryRouter><Sidebar/></MemoryRouter>);});
 await act(async () => {window.dispatchEvent(new KeyboardEvent("keydown",{key:"s",ctrlKey:true,shiftKey:true}));});
 expect(host.querySelector(".sidebar.collapsed")).not.toBeNull();
 expect(host.querySelectorAll(".sidebar a")).toHaveLength(7);
 await act(async () => {window.dispatchEvent(new KeyboardEvent("keydown",{key:"s",ctrlKey:true}));});
 expect(host.querySelector(".sidebar.collapsed")).not.toBeNull();
 await act(async () => {window.dispatchEvent(new KeyboardEvent("keydown",{key:"s",ctrlKey:true,shiftKey:true}));});
 expect(host.querySelector(".sidebar.collapsed")).toBeNull();
 await act(async () => {root.unmount();});
});

import { vi } from "vitest";
import { TranscriptsList } from "../../transcripts/TranscriptsList";
it("opens notes by keyboard without activating the row from its menu", async () => {
 const host = document.createElement("div"), root = createRoot(host), select = vi.fn(), noop = () => {};
 await act(async () => {root.render(<TranscriptsList transcripts={[{id:"local-review",title:"Review",tags:[],duration_seconds:1,created_at:new Date().toISOString(),updated_at:new Date().toISOString()}]} selectedId={null} searchQuery="" selectedTags={[]} isLoading={false} onSelect={select} onSearchChange={noop} onTagToggle={noop} onRefresh={noop} onContextMenu={noop} onBulkDelete={noop}/>);});
 const row = host.querySelector(".tl-item")!;
 await act(async () => {row.dispatchEvent(new KeyboardEvent("keydown",{key:"Enter",bubbles:true}));});
 expect(select).toHaveBeenCalledWith("local-review");
 select.mockClear();
 await act(async () => {row.querySelector("button")!.dispatchEvent(new KeyboardEvent("keydown",{key:"Enter",bubbles:true}));});
 expect(select).not.toHaveBeenCalled();
 await act(async () => {root.unmount();});
});
