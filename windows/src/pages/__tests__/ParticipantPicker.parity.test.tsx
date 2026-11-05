import { act } from "react";
import { createRoot } from "react-dom/client";
import { expect, it, vi } from "vitest";
import { ParticipantPicker } from "../ParticipantPicker";
import { usePeopleDirectoryStore } from "../../stores/peopleDirectoryStore";
import { useRecordingStore } from "../../stores/recordingStore";

it("searches names, aliases and organizations while retaining hidden participant selections", async () => {
  const previousPeople = usePeopleDirectoryStore.getState().people;
  const previousIds = useRecordingStore.getState().selectedParticipantIds;
  const makePerson = usePeopleDirectoryStore.getState().createDefaultPerson;
  const first = makePerson({ name: "Lisa", aliases: ["Projectleider"], organization: "Acme" });
  const second = makePerson({ name: "Sam", organization: "Yinga" });
  usePeopleDirectoryStore.setState({ people: [first, second] });
  useRecordingStore.setState({ selectedParticipantIds: [first.id] });
  const container = document.createElement("div");
  document.body.appendChild(container);
  const root = createRoot(container);
  const onClose = vi.fn();
  try {
    await act(async () => { root.render(<ParticipantPicker onClose={onClose} />); });
    const input = container.querySelector<HTMLInputElement>('input[type="search"]')!;
    async function search(value: string) {
      await act(async () => {
        Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value")!.set!.call(input, value);
        input.dispatchEvent(new Event("input", { bubbles: true }));
      });
    }
    for (const query of ["LISA", "projectleider", "acme"]) {
      await search(query);
      expect(container.querySelectorAll('input[type="checkbox"]')).toHaveLength(1);
      expect(container.querySelector<HTMLInputElement>('input[type="checkbox"]')!.checked).toBe(true);
    }
    await search("YINGA");
    await act(async () => { container.querySelector<HTMLInputElement>('input[type="checkbox"]')!.click(); });
    expect(useRecordingStore.getState().selectedParticipantIds).toEqual([first.id, second.id]);
    await search("Onbekend");
    expect(container.textContent).toContain("Geen resultaten");
    expect(container.querySelectorAll('input[type="checkbox"]')).toHaveLength(0);
    await act(async () => { container.querySelector('dialog')!.dispatchEvent(new Event("cancel", { cancelable: true })); });
    expect(onClose).toHaveBeenCalledOnce();
  } finally {
    await act(async () => { root.unmount(); });
    container.remove();
    usePeopleDirectoryStore.setState({ people: previousPeople });
    useRecordingStore.setState({ selectedParticipantIds: previousIds });
  }
});
