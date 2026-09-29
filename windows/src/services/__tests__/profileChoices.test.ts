import { beforeEach, expect, it } from "vitest";
import { DEFAULT_PROFILES } from "../../types";
import { useProfilesStore } from "../../stores/profilesStore";
import { saveProfileForMode } from "../profileActions";
import { shouldBlockForLocalNotes } from "../routeAccess";

beforeEach(() => useProfilesStore.setState({ profiles: DEFAULT_PROFILES, localProfiles: [] }));

it("saves and selects a custom profile in local mode without a server", async () => {
  const profile = { id: "local-test", name: "Eigen", notule_prompt: "Vat samen", is_default: false };
  await saveProfileForMode("local", profile);
  expect(useProfilesStore.getState().getProfile("local-test")?.name).toBe("Eigen");
  expect(useProfilesStore.getState().profiles.map((p) => p.id).slice(0, 7))
    .toEqual(DEFAULT_PROFILES.map((p) => p.id));
});

it("hides legacy built-ins from new recording choices but keeps custom profiles", async () => {
  const { currentProfileChoices } = await import("../../stores/profilesStore");
  const choices = currentProfileChoices([
    { id: "zakelijk", name: "Zakelijk", is_default: true },
    { id: "custom-old", name: "Eigen oud", is_default: false },
  ]);
  expect(choices.some((p) => p.id === "zakelijk")).toBe(false);
  expect(choices.some((p) => p.id === "custom-old")).toBe(true);
});

it("restores local profiles after cloud profiles replace the visible choices", async () => {
  await saveProfileForMode("local", { id: "local-1", name: "Lokaal", notule_prompt: "Eigen", is_default: false });
  useProfilesStore.getState().setProfiles(DEFAULT_PROFILES);
  useProfilesStore.getState().showLocalProfiles();
  expect(useProfilesStore.getState().getProfile("local-1")?.name).toBe("Lokaal");
});

it("does not block cloud startup when local notes fail to load", () => {
  expect(shouldBlockForLocalNotes("cloud", false)).toBe(false);
  expect(shouldBlockForLocalNotes("local", false)).toBe(true);
});
