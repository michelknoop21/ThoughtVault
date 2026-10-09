import { act } from "react";
import { createRoot } from "react-dom/client";
import { expect, it, vi } from "vitest";
import { useConfirmation } from "../useConfirmation";

vi.mock("../DesktopDialog", () => ({ DesktopDialog: ({ children, onClose }: any) =>
  <div role="dialog"><button onClick={onClose}>Dismiss</button>{children}</div> }));

it("resolves app confirmations for accept, cancellation and unmount", async () => {
  let confirm!: ReturnType<typeof useConfirmation>["confirm"];
  function Harness() {
    const dialog = useConfirmation(); confirm = dialog.confirm; return dialog.confirmation;
  }
  const container = document.createElement("div");
  const root = createRoot(container);
  await act(async () => root.render(<Harness />));
  let result!: Promise<boolean>;
  await act(async () => { result = confirm("Opname blijft bewaard", "Opname stoppen", "Stoppen"); });
  expect(container.textContent).toContain("Opname blijft bewaard");
  await act(async () => (Array.from(container.querySelectorAll("button")).find(b => b.textContent === "Stoppen")!).click());
  expect(await result).toBe(true);
  await act(async () => { result = confirm("Test", "Annuleren", "Doorgaan"); });
  await act(async () => container.querySelector("button")!.click());
  expect(await result).toBe(false);
  await act(async () => { result = confirm("Test", "Sluiten", "Doorgaan"); });
  await act(async () => root.unmount());
  expect(await result).toBe(false);
});
