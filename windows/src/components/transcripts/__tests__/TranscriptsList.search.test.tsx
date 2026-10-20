import { act } from "react";
import { createRoot } from "react-dom/client";
import { expect, it, vi } from "vitest";
import { TranscriptsList } from "../TranscriptsList";

it("searches titles, transcript, visible notes and tags, ignoring case and surrounding whitespace", async () => {
  const container = document.createElement("div");
  const root = createRoot(container);
  const noop = vi.fn();
  const transcripts = [
    { id: "one", title: "Vergadering", raw_transcription: "Alex doet de installatie", notule_html: '<style>.hidden { color: red }</style><p>QA Windows 19 oktober</p><p>Bewerken gecontroleerd &amp; heropend.</p>', tags: ["Yinga"], duration_seconds: 1, created_at: new Date().toISOString(), updated_at: new Date().toISOString() },
    { id: "two", title: "Andere notule", tags: [], duration_seconds: 1, created_at: new Date().toISOString(), updated_at: new Date().toISOString() },
  ];
  for (const query of ["  aLEX  ", "YINGA", "vergadering", "qa WINDOWS 19 oktober", "oktober Bewerken", "gecontroleerd & heropend"]) {
    await act(async () => root.render(<TranscriptsList transcripts={transcripts} selectedId={null} searchQuery={query} selectedTags={[]} isLoading={false} onSelect={noop} onSearchChange={noop} onTagToggle={noop} onRefresh={noop} onContextMenu={noop} onBulkDelete={noop} />));
    expect(container.querySelectorAll(".tl-item-title")).toHaveLength(1);
    expect(container.querySelector(".tl-item-title")?.textContent).toBe("Vergadering");
  }
  expect(container.querySelector(".tl-item-preview")?.textContent).not.toContain("color: red");
  expect(container.querySelector(".tl-item-preview")?.textContent).toContain("oktober Bewerken");
  await act(async () => root.unmount());
});
