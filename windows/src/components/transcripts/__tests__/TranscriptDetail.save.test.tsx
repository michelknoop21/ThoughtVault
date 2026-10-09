import { act } from "react";
import { createRoot } from "react-dom/client";
import { expect, it, vi } from "vitest";
const dictionary = vi.hoisted(()=>({entries:[],hydrate:vi.fn(async()=>{}),save:vi.fn(async()=>{})}));
vi.mock("../../../stores/personalCorrectionsStore",()=>({usePersonalCorrectionsStore:{getState:()=>dictionary}}));
import { DEFAULT_PROFILES } from "../../../types";
import { TranscriptDetail } from "../TranscriptDetail";

it("keeps an edited notule open when saving fails", async () => {
  const save = vi.fn().mockRejectedValue(new Error("Schijf vol"));
  const container = document.createElement("div");
  const root = createRoot(container);
  const note = {
    id: "local-note", title: "Overleg", notule_html: "<p>Oude tekst</p>",
    duration_seconds: 10, tags: [], created_at: new Date().toISOString(), updated_at: new Date().toISOString(),
  };
  const noop = vi.fn();
  await act(async () => {
    root.render(<TranscriptDetail transcript={note} regeneratingId={null} onBack={noop}
      onRegenerate={noop} onDelete={noop} onUpdateTitle={async () => {}} onSaveNotule={save}
      onCopy={noop} onExportPDF={noop} onExportTXT={noop} onExportMarkdown={noop}
      onExportHTML={noop} onExportObsidian={noop} onOpenTags={noop} onGenerateTitle={noop} />);
  });
  await act(async () => { container.querySelector<HTMLButtonElement>('[title="Notule bewerken"]')!.click(); });
  const editor = container.querySelector<HTMLDivElement>('[aria-label="Notule bewerken"]')!;
  await act(async () => {
    editor.innerHTML = "<p>Mijn concept blijft bewaard</p>";
    editor.dispatchEvent(new Event("input", { bubbles: true }));
  });
  await act(async () => {
    [...container.querySelectorAll<HTMLButtonElement>("button")].find((button) => button.textContent?.includes("Opslaan"))!.click();
  });
  expect(save).toHaveBeenCalledWith("local-note", "<p>Mijn concept blijft bewaard</p>");
  expect(container.querySelector<HTMLDivElement>('[aria-label="Notule bewerken"]')?.textContent).toBe("Mijn concept blijft bewaard");
  await act(async () => { root.unmount(); });
});

it("allows regeneration from a saved transcript without a notule", async () => {
  const regenerate = vi.fn();
  const noop = vi.fn();
  const container = document.createElement("div");
  const root = createRoot(container);
  const transcript = {
    id: "local-partial", title: "Transcriptie", raw_transcription: "Besproken acties.",
    duration_seconds: 10, tags: [], created_at: new Date().toISOString(), updated_at: new Date().toISOString(),
  };
  await act(async () => {
    root.render(<TranscriptDetail transcript={transcript} regeneratingId={null} onBack={noop}
      onRegenerate={regenerate} onDelete={noop} onUpdateTitle={async () => {}} onSaveNotule={async () => {}}
      onCopy={noop} onExportPDF={noop} onExportTXT={noop} onExportMarkdown={noop}
      onExportHTML={noop} onExportObsidian={noop} onImportObsidian={noop} onOpenTags={noop} onGenerateTitle={noop} />);
  });
  const button = container.querySelector<HTMLButtonElement>('[title="Notulen opnieuw genereren met AI"]');
  expect(button).not.toBeNull();
  await act(async () => { button!.click(); });
  expect(regenerate).toHaveBeenCalledWith(transcript);
  await act(async () => { root.unmount(); });
});

it("retains the selected-word correction after a failed note save and learns only after success", async()=>{
  const save = vi.fn().mockRejectedValueOnce(new Error("Schijf vol")).mockResolvedValue(undefined);
  dictionary.save.mockClear();
  const container = document.createElement("div");document.body.append(container);
  const root = createRoot(container); const noop=vi.fn();
  const note={id:"local-word",title:"Overleg",profile_name:DEFAULT_PROFILES[0].name,raw_transcription:"Jengo",notule_html:"<p>Jengo</p>",duration_seconds:10,tags:[],created_at:new Date().toISOString(),updated_at:new Date().toISOString()};
  await act(async()=>{root.render(<TranscriptDetail transcript={note} regeneratingId={null} onBack={noop} onRegenerate={noop} onDelete={noop} onUpdateTitle={async()=>{}} onSaveNotule={save} onCopy={noop} onExportPDF={noop} onExportTXT={noop} onExportMarkdown={noop} onExportHTML={noop} onExportObsidian={noop} onImportObsidian={noop} onOpenTags={noop} onGenerateTitle={noop}/>);});
  const node=container.querySelector(".td-doc-body p")!.firstChild!;
  const range=document.createRange();range.selectNodeContents(node);window.getSelection()!.removeAllRanges();window.getSelection()!.addRange(range);
  await act(async()=>{[...container.querySelectorAll("button")].find(b=>b.textContent==="Woord corrigeren")!.click();});
  const inputs=container.querySelectorAll<HTMLInputElement>(".correction-dialog input.input");
  expect(inputs[1].value).toBe("Jengo");
  expect(container.querySelector<HTMLSelectElement>(".correction-dialog select")!.value).toBe(DEFAULT_PROFILES[0].id);
  await act(async()=>{
    Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,"value")!.set!.call(inputs[0],"Yinga");
    inputs[0].dispatchEvent(new Event("input",{bubbles:true}));
  });
  await act(async()=>{container.querySelector<HTMLButtonElement>(".correction-dialog .btn-accent")!.click();});
  expect(save).toHaveBeenCalledWith("local-word","<p>Yinga</p>");
  expect(container.textContent).toContain("Schijf vol");expect(inputs[0].value).toBe("Yinga");expect(dictionary.save).not.toHaveBeenCalled();
  await act(async()=>{container.querySelector<HTMLButtonElement>(".correction-dialog .btn-accent")!.click();});
  expect(dictionary.save).toHaveBeenCalledOnce();expect(container.querySelector("dialog")).toBeNull();expect(note.raw_transcription).toBe("Jengo");
  await act(async()=>{root.unmount();});container.remove();
});
