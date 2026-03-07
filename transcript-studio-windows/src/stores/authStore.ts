import { create } from "zustand";
import { persist } from "zustand/middleware";
import { invoke } from "@tauri-apps/api/core";
import type { User } from "../types";

const CREDENTIAL_KEY = "auth_token";

/** Decode JWT payload without verification (for reading expiry). */
function decodeJwtExpiry(token: string): number | null {
  try {
    const parts = token.split(".");
    if (parts.length !== 3) return null;
    const payload = JSON.parse(atob(parts[1]));
    return typeof payload.exp === "number" ? payload.exp * 1000 : null;
  } catch {
    return null;
  }
}

interface AuthState {
  token: string | null;
  user: User | null;
  isAuthenticated: boolean;
  tokenExpiresAt: number | null;
  setToken: (token: string) => void;
  setUser: (user: User) => void;
  updateUserName: (name: string) => void;
  logout: () => void;
  loadTokenFromKeyring: () => Promise<void>;
  isTokenExpired: () => boolean;
}

export const useAuthStore = create<AuthState>()(
  persist(
    (set, get) => ({
      token: null,
      user: null,
      isAuthenticated: false,
      tokenExpiresAt: null,
      setToken: (token) => {
        // Store token in OS keyring, not localStorage
        invoke("store_credential", { key: CREDENTIAL_KEY, value: token }).catch((e) =>
          console.error("Failed to store token in keyring:", e)
        );
        const expiresAt = decodeJwtExpiry(token) ?? Date.now() + 24 * 60 * 60 * 1000;
        set({ token, isAuthenticated: true, tokenExpiresAt: expiresAt });
      },
      setUser: (user) => set({ user }),
      updateUserName: (name) => set((state) => ({
        user: state.user ? { ...state.user, name } : null,
      })),
      logout: () => {
        invoke("delete_credential", { key: CREDENTIAL_KEY }).catch(() => {});
        set({ token: null, user: null, isAuthenticated: false, tokenExpiresAt: null });
      },
      loadTokenFromKeyring: async () => {
        try {
          const token = await invoke<string | null>("load_credential", { key: CREDENTIAL_KEY });
          if (token) {
            const expiresAt = decodeJwtExpiry(token) ?? Date.now() + 24 * 60 * 60 * 1000;
            if (expiresAt > Date.now()) {
              set({ token, isAuthenticated: true, tokenExpiresAt: expiresAt });
            } else {
              // Token expired — clean up
              invoke("delete_credential", { key: CREDENTIAL_KEY }).catch(() => {});
            }
          }
        } catch {
          // Keyring unavailable — token stays null
        }
      },
      isTokenExpired: () => {
        const { tokenExpiresAt } = get();
        return tokenExpiresAt != null && Date.now() >= tokenExpiresAt;
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
