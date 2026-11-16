import { create } from "zustand";

/** Session-only state: true once the Obsidian link failed, until a successful test or an app restart. */
interface ObsidianLinkState {
  broken: boolean;
  setBroken: (broken: boolean) => void;
}

export const useObsidianLinkStore = create<ObsidianLinkState>((update) => ({
  broken: false,
  setBroken: (broken) => update({ broken }),
}));
