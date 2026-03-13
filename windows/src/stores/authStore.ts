import { create } from "zustand";
import { persist } from "zustand/middleware";
import { invoke } from "@tauri-apps/api/core";
import type { User } from "../types";

const CREDENTIAL_KEY = "auth_token";

interface AuthState {
  token: string | null;
  user: User | null;
  isAuthenticated: boolean;
  isInitializing: boolean;
  setToken: (token: string) => void;
  setUser: (user: User) => void;
  updateUserName: (name: string) => void;
  logout: () => void;
  loadTokenFromKeyring: () => Promise<void>;
}

export const useAuthStore = create<AuthState>()(
  persist(
    (set) => ({
      token: null,
      user: null,
      isAuthenticated: false,
      isInitializing: true,
      setToken: (token) => {
        // Store token in OS keyring, not localStorage
        invoke("store_credential", { key: CREDENTIAL_KEY, value: token }).catch((e) =>
          console.error("Failed to store token in keyring:", e)
        );
        set({ token, isAuthenticated: true });
      },
      setUser: (user) => set({ user }),
      updateUserName: (name) => set((state) => ({
        user: state.user ? { ...state.user, name } : null,
      })),
      logout: () => {
        invoke("delete_credential", { key: CREDENTIAL_KEY }).catch(() => {});
        set({ token: null, user: null, isAuthenticated: false });
      },
      loadTokenFromKeyring: async () => {
        try {
          const token = await invoke<string | null>("load_credential", { key: CREDENTIAL_KEY });
          if (token) {
            set({ token, isAuthenticated: true });
          }
        } catch {
          // Keyring unavailable — token stays null
        } finally {
          set({ isInitializing: false });
        }
      },
    }),
    {
      name: "auth-store",
      // Only persist user info to localStorage — token goes to keyring
      partialize: (state) => ({ user: state.user }),
      onRehydrateStorage: () => (state) => {
        // After rehydration, load token from keyring
        if (state) {
          state.loadTokenFromKeyring();
        }
      },
    }
  )
);
