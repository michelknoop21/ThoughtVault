import type { ProcessingMode, Profile } from "../types";
import { useProfilesStore } from "../stores/profilesStore";
import { api } from "./api";

export async function saveProfileForMode(mode: ProcessingMode, profile: Profile, editing = false): Promise<void> {
  const store = useProfilesStore.getState();
  if (mode === "local") {
    store.saveLocalProfile(profile);
    return;
  }
  if (editing) {
    await api.updateProfile(profile.id, profile);
    store.updateProfile(profile.id, profile);
  } else {
    const created = await api.createProfile(profile);
    store.addProfile({ ...profile, id: created.id });
  }
}

export async function deleteProfileForMode(mode: ProcessingMode, id: string): Promise<void> {
  if (mode === "cloud") {
    await api.deleteProfile(id);
    useProfilesStore.getState().deleteProfile(id);
  } else {
    useProfilesStore.getState().deleteLocalProfile(id);
  }
}
