import { act } from "react";
import { createRoot } from "react-dom/client";
import { expect, it, vi } from "vitest";
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
