import { act } from "react";
import { createRoot } from "react-dom/client";
import { expect, it, vi } from "vitest";
import { TranscriptsList } from "../TranscriptsList";

// Selection mode keeps the selection when the user cancels the delete, and clears it once deleted.
for (const deleted of [false, true]) {
  it(deleted ? "clears the selection after the delete went through" : "keeps the selection when the delete is cancelled", async () => {
    const container = document.createElement("div");
    const root = createRoot(container);
    const noop = vi.fn();
    const onBulkDelete = vi.fn(async () => deleted);
    const transcripts = [{ id: "local-a", title: "Vergadering", tags: [], duration_seconds: 1, created_at: new Date().toISOString(), updated_at: new Date().toISOString() }];
    await act(async () => root.render(<TranscriptsList transcripts={transcripts} selectedId={null} searchQuery="" selectedTags={[]} isLoading={false} onSelect={noop} onSearchChange={noop} onTagToggle={noop} onRefresh={noop} onContextMenu={noop} onBulkDelete={onBulkDelete} />));
    // The period filter also has an "Alles" button, so look inside the selection bar.
    const button = (text: string, scope: ParentNode = container) => [...scope.querySelectorAll("button")].find(b => b.title === text || b.textContent?.trim().startsWith(text))!;
    await act(async () => button("Selectiemodus").click());
    const bar = () => container.querySelector(".tl-bulk-bar")!;
    await act(async () => button("Alles", bar()).click());
    await act(async () => button("Verwijder", bar()).click());
    expect(onBulkDelete).toHaveBeenCalledWith(["local-a"]);
    expect(container.textContent?.includes("1 geselecteerd")).toBe(!deleted);
    await act(async () => root.unmount());
  });
}
