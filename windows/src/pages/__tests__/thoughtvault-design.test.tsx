import { describe, expect, it, vi } from "vitest";
import { act } from "react";
import { createRoot } from "react-dom/client";
import { renderToStaticMarkup } from "react-dom/server";
import { MemoryRouter } from "react-router-dom";
import { RecordingPage } from "../RecordingPage";
import { useRecordingStore } from "../../stores/recordingStore";
import { useLocalTranscriptsStore } from "../../stores/localTranscriptsStore";
import { HomePage } from "../HomePage";
import { SettingsPage } from "../SettingsPage";
import { TranscriptsList } from "../../components/transcripts/TranscriptsList";
import { Sidebar } from "../../components/layout/Sidebar";

vi.mock("../../hooks/useAudioLevel", () => ({useAudioLevel: () => 0, useAudioLevelsRef: () => ({current:[]})}));

describe("current ThoughtVault interface", () => {
  it("keeps the approved settings navigation and new provider controls together", () => {
    const root = document.createElement("div");
    root.innerHTML = renderToStaticMarkup(<SettingsPage />);
    const tabs = root.querySelectorAll('nav[aria-label="Instellingen"] button');
    expect([...tabs].map(tab => tab.textContent)).toEqual(["Algemeen", "Verwerking", "Notulen", "Agenda", "Obsidian", "Geavanceerd"]);
    expect(root.querySelector('.processing-columns .processing-side')).not.toBeNull();
    expect(root.textContent).toContain("Jouw pc");
    expect(root.textContent).toContain("Ollama Cloud");
    expect(root.textContent).toContain("Cloudprovider");
    expect(root.textContent).toContain("Claude en ChatGPT");
    expect(root.textContent).not.toContain("Onboarding opnieuw doorlopen");
  });

  it("keeps source and profile selection available in the studio, with phase-correct transport", async () => {
    for (const phase of ["idle", "recording", "paused"] as const) {
      useRecordingStore.setState({phase});
      const root = document.createElement("div");
      const mounted = createRoot(root);
      await act(async () => { mounted.render(<MemoryRouter><RecordingPage /></MemoryRouter>); });
      expect(root.querySelector('select[aria-label="Bron"]')).not.toBeNull();
      expect(root.querySelector('select[aria-label="Opnameprofiel"]')).not.toBeNull();
      expect(root.querySelector('select[aria-label="Bron"]')?.hasAttribute('disabled')).toBe(phase !== "idle");
      expect(root.querySelector('button[aria-label="Start opname"]') !== null).toBe(phase === "idle");
      expect(root.querySelector('button[aria-label="Stop en verwerk"]') !== null).toBe(phase !== "idle");
      if (phase !== "idle") expect(root.querySelector(`button[aria-label="${phase === "paused" ? "Hervat opname" : "Pauzeer opname"}"]`)).not.toBeNull();
      await act(async () => { mounted.unmount(); });
    }
    useRecordingStore.setState({phase:"idle"});
  });

  it("shows local recent notes away from Home without duplicating the Home list", async () => {
    const saved = useLocalTranscriptsStore.getState().items;
    useLocalTranscriptsStore.setState({items:[{id:"local-review",title:"Bestaande notule",duration_seconds:120,tags:[],created_at:"2026-10-07T12:00:00Z",updated_at:"2026-10-07T12:00:00Z"}]});
    for (const path of ["/recording", "/"]) {
      const container = document.createElement("div");
      const mounted = createRoot(container);
      await act(async () => { mounted.render(<MemoryRouter initialEntries={[path]}><Sidebar /></MemoryRouter>); });
      expect(container.querySelector('[aria-label="Recente notulen"]') !== null).toBe(path !== "/");
      if (path !== "/") expect(container.textContent).toContain("Bestaande notule");
      await act(async () => { mounted.unmount(); });
    }
    useLocalTranscriptsStore.setState({items:saved});
  });

  it("opens a note by keyboard without opening it when its menu receives Enter", async () => {
    const container = document.createElement("div");
    const mounted = createRoot(container);
    const select = vi.fn();
    const noop = () => {};
    await act(async () => { mounted.render(<TranscriptsList transcripts={[{id:"local-review",title:"Bestaande notule",duration_seconds:120,tags:[],created_at:new Date().toISOString(),updated_at:new Date().toISOString()}]} selectedId={null} searchQuery="" selectedTags={[]} isLoading={false} onSelect={select} onSearchChange={noop} onTagToggle={noop} onRefresh={noop} onContextMenu={noop} onBulkDelete={noop} />); });
    const row = container.querySelector('.tl-item')!;
    await act(async () => { row.dispatchEvent(new KeyboardEvent('keydown',{key:'Enter',bubbles:true})); });
    expect(select).toHaveBeenCalledWith("local-review");
    select.mockClear();
    await act(async () => { row.querySelector('button')!.dispatchEvent(new KeyboardEvent('keydown',{key:'Enter',bubbles:true})); });
    expect(select).not.toHaveBeenCalled();
    await act(async () => { mounted.unmount(); });
  });

  it("renders the current Home composition and keeps its actions reachable", () => {
    const html = renderToStaticMarkup(<MemoryRouter><Sidebar /><HomePage /></MemoryRouter>);
    const root = document.createElement("div");
    root.innerHTML = html;
    expect(root.querySelector('.thoughtvault-home[data-theme="dark"]')).not.toBeNull();
    expect(root.querySelector('input[aria-label="Zoek in je notulen"]')).not.toBeNull();
    expect(root.querySelector('section[aria-label="Nieuwe opname"]')).not.toBeNull();
    expect(root.querySelector('button[aria-label="Nieuwe opname voorbereiden"]')).not.toBeNull();
    expect(root.querySelector('section[aria-label="Snel vastleggen"]')).not.toBeNull();
    expect(root.textContent).toContain("Recente notities");
    expect(root.textContent).not.toContain("Wat wil je vandaag transcriberen?");
    expect(root.textContent).not.toContain("Recente sessies");
    for (const href of ["/recording", "/tasks", "/transcripts", "/profiles", "/people", "/settings"])
      expect(root.querySelector(`nav a[href="${href}"]`)).not.toBeNull();
    expect(root.querySelector('nav img[alt="ThoughtVault"]')).not.toBeNull();
  });
});
