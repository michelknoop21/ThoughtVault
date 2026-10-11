import { act } from "react";
import { createRoot } from "react-dom/client";
import { expect, it, vi } from "vitest";
import { TranscriptsList } from "../TranscriptsList";

it("searches titles, raw transcript and tags, ignoring case and surrounding whitespace", async () => {
  const container = document.createElement("div");
  const root = createRoot(container);
  const noop = vi.fn();
  const transcripts = [
    { id: "one", title: "Vergadering", raw_transcription: "Alex doet de installatie", tags: ["Yinga"], duration_seconds: 1, created_at: new Date().toISOString(), updated_at: new Date().toISOString() },
    { id: "two", title: "Andere notule", tags: [], duration_seconds: 1, created_at: new Date().toISOString(), updated_at: new Date().toISOString() },
  ];
  for (const query of ["  aLEX  ", "YINGA", "vergadering"]) {
    await act(async () => root.render(<TranscriptsList transcripts={transcripts} selectedId={null} searchQuery={query} selectedTags={[]} isLoading={false} onSelect={noop} onSearchChange={noop} onTagToggle={noop} onRefresh={noop} onContextMenu={noop} onBulkDelete={noop} />));
    expect(container.querySelectorAll(".tl-item-title")).toHaveLength(1);
    expect(container.querySelector(".tl-item-title")?.textContent).toBe("Vergadering");
  }
  await act(async () => root.unmount());
});
