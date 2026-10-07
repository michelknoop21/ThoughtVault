import { act } from "react";
import { createRoot } from "react-dom/client";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import { afterEach, expect, it, vi } from "vitest";
import { LoginPage } from "../LoginPage";
import { useSettingsStore } from "../../stores/settingsStore";

vi.mock("../../components/layout/TitleBar", () => ({ TitleBar: () => null }));
vi.mock("../../components/brand/BrandFooter", () => ({ BrandFooter: () => null }));

afterEach(() => {
  useSettingsStore.getState().updateSettings({ processing_mode: "cloud", notulen_provider: "cloud" });
});

it("enters local recording without asking for an account", async () => {
  const container = document.createElement("div");
  const root = createRoot(container);
  await act(async () => {
    root.render(<MemoryRouter initialEntries={["/login"]}><Routes>
      <Route path="/login" element={<LoginPage />} />
      <Route path="/recording" element={<div>Lokale opname</div>} />
    </Routes></MemoryRouter>);
  });
  await act(async () => {
    [...container.querySelectorAll("button")]
      .find((button) => button.textContent?.includes("Lokaal gebruiken zonder account"))!.click();
  });
  expect(container.textContent).toContain("Lokale opname");
  expect(useSettingsStore.getState().processing_mode).toBe("local");
  await act(async () => { root.unmount(); });
});
