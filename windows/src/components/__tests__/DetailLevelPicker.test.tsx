import { act } from "react";
import { createRoot } from "react-dom/client";
import { afterEach, expect, it } from "vitest";
import { ProfileDetailLevelPicker } from "../DetailLevelPicker";
import { useSettingsStore } from "../../stores/settingsStore";
import { chooseDetailLevel, regenerateDetailLevel } from "../../services/notuleDetailLevel";

afterEach(() => { useSettingsStore.getState().updateSettings({ profile_detail_levels: {} }); });

async function render(id: string) {
  const container = document.createElement("div");
  const root = createRoot(container);
  await act(async () => { root.render(<ProfileDetailLevelPicker profile={{ id, name: id }} />); });
  const button = (label: string) => Array.from(container.querySelectorAll<HTMLButtonElement>("button")).find((b) => b.textContent === label)!;
  const pressed = () => container.querySelector('button[aria-pressed="true"]')?.textContent;
  return { container, root, button, pressed };
}

it("shows the profile's effective level and stores the user's choice per profile", async () => {
  const { container, root, button, pressed } = await render("executive");
  expect(pressed()).toBe("Kort");
  expect(container.textContent).toContain("Kort: besluiten, acties en bedragen; ongeveer 6% van het gesprek, 1.500 tot 4.000 tekens");

  await act(async () => { button("Volledig").click(); });
  expect(useSettingsStore.getState().profile_detail_levels).toEqual({ executive: "volledig" });
  expect(pressed()).toBe("Volledig");

  // Picking the profile's own default removes the override.
  await act(async () => { button("Kort").click(); });
  expect(useSettingsStore.getState().profile_detail_levels).toEqual({});
  expect(pressed()).toBe("Kort");
  await act(async () => { root.unmount(); });
});

it("shows no picker for a profile without a level", async () => {
  for (const id of ["promptnotitie", "eigen-profiel"]) {
    const { container, root } = await render(id);
    expect(container.innerHTML).toBe("");
    await act(async () => { root.unmount(); });
  }
});

it("keeps other profiles' choices and preselects by the regenerate rule", () => {
  const executive = { id: "executive", detail_level: "kort" };
  expect(chooseDetailLevel({ brainstorm: "kort" }, executive, "normaal")).toEqual({ brainstorm: "kort", executive: "normaal" });
  expect(chooseDetailLevel({ brainstorm: "kort", executive: "normaal" }, executive, "kort")).toEqual({ brainstorm: "kort" });

  const transcript = { profile_id: "executive", detail_level: "normaal" as const };
  expect(regenerateDetailLevel(transcript, executive)).toBe("normaal");
  expect(regenerateDetailLevel(transcript, { id: "klantgesprek", detail_level: "normaal" }, { klantgesprek: "volledig" })).toBe("volledig");
  expect(regenerateDetailLevel({ profile_id: "executive" }, executive)).toBe("kort");
});
