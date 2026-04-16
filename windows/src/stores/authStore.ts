import { create } from "zustand";
import { persist } from "zustand/middleware";
import { invoke } from "@tauri-apps/api/core";
import { api } from "../services/api";
import type { User } from "../types";

const CREDENTIAL_KEY = "auth_token";
const SAVED_EMAIL_KEY = "saved_email";
const SAVED_PASSWORD_KEY = "saved_password";
const REMEMBER_ME_KEY = "remember_me";

interface AuthState {
  token: string | null;
  user: User | null;
  isAuthenticated: boolean;
  isInitializing: boolean;
  rememberMe: boolean;
  savedEmail: string;
  pendingTwoFactor: { tempToken: string; email: string } | null;
  setToken: (token: string) => void;
  setUser: (user: User) => void;
  updateUserName: (name: string) => void;
  setRememberMe: (value: boolean) => void;
  setSavedEmail: (email: string) => void;
  saveCredentials: (email: string, password: string) => Promise<void>;
  clearSavedCredentials: () => Promise<void>;
  clearPendingTwoFactor: () => void;
  logout: () => void;
  loadTokenFromKeyring: () => Promise<void>;
}

/** Check if an error is likely a network/transient issue (not an auth failure). */
function isNetworkError(err: unknown): boolean {
  const msg = err instanceof Error ? err.message : String(err);
  const lower = msg.toLowerCase();
  return (
    lower.includes("network") ||
    lower.includes("fetch") ||
    lower.includes("timeout") ||
    lower.includes("dns") ||
    lower.includes("econnrefused") ||
    lower.includes("enotfound") ||
    lower.includes("connection") ||
    lower.includes("offline") ||
    lower.includes("serverfout")
  );
}

export const useAuthStore = create<AuthState>()(
  persist(
    (set, get) => ({
      token: null,
      user: null,
      isAuthenticated: false,
      isInitializing: true,
      rememberMe: false,
      savedEmail: "",
      pendingTwoFactor: null,

      setToken: (token) => {
        invoke("store_credential", { key: CREDENTIAL_KEY, value: token }).catch((e) =>
          console.error("Failed to store token in keyring:", e)
        );
        set({ token, isAuthenticated: true });
      },

      setUser: (user) => set({ user }),

      updateUserName: (name) => set((state) => ({
        user: state.user ? { ...state.user, name } : null,
      })),

      setRememberMe: (value) => set({ rememberMe: value }),

      setSavedEmail: (email) => set({ savedEmail: email }),

      saveCredentials: async (email, password) => {
        try {
          await Promise.all([
            invoke("store_credential", { key: SAVED_EMAIL_KEY, value: email }),
            invoke("store_credential", { key: SAVED_PASSWORD_KEY, value: password }),
            invoke("store_credential", { key: REMEMBER_ME_KEY, value: "true" }),
          ]);
        } catch (e) {
          console.error("Failed to save credentials:", e);
        }
      },

      clearSavedCredentials: async () => {
        try {
          await Promise.all([
            invoke("delete_credential", { key: SAVED_EMAIL_KEY }).catch(() => {}),
            invoke("delete_credential", { key: SAVED_PASSWORD_KEY }).catch(() => {}),
            invoke("delete_credential", { key: REMEMBER_ME_KEY }).catch(() => {}),
          ]);
        } catch {
          // ignore cleanup errors
        }
      },

      clearPendingTwoFactor: () => set({ pendingTwoFactor: null }),

      logout: () => {
        invoke("delete_credential", { key: CREDENTIAL_KEY }).catch(() => {});
        // Clear password from keyring but keep savedEmail + rememberMe
        // so the username is pre-filled on the next login screen
        invoke("delete_credential", { key: SAVED_PASSWORD_KEY }).catch(() => {});
        invoke("delete_credential", { key: REMEMBER_ME_KEY }).catch(() => {});
        set({ token: null, user: null, isAuthenticated: false, pendingTwoFactor: null });
      },

      loadTokenFromKeyring: async () => {
        try {
          // Step 1: Try loading existing token
          const token = await invoke<string | null>("load_credential", { key: CREDENTIAL_KEY });

          if (token) {
            // Token found — trust it immediately (validate non-blocking later)
            set({ token, isAuthenticated: true });
            try {
              const profiles = await api.getProfiles();
              if (profiles !== null) {
                // Token is valid, we're done
                return;
              }
            } catch {
              // Validation failed — token might still work, keep it and
              // let individual requests handle 401s. Only try auto-login
              // if remember-me is set, but NEVER downgrade isAuthenticated.
              console.log("[Auth] Token validation failed, keeping token");
            }
          }

          // Step 2: Check for saved credentials (remember me)
          let rememberFlag: string | null = null;
          try {
            rememberFlag = await invoke<string | null>("load_credential", { key: REMEMBER_ME_KEY });
          } catch {
            // No remember me flag
          }

          if (rememberFlag !== "true") {
            // No saved credentials — if we had a token, keep it (user can still work
            // until it actually fails on a real request). Otherwise show login.
            if (!token) {
              set({ isAuthenticated: false, token: null });
            }
            return;
          }

          // Step 3: Load saved email + password
          let savedEmail: string | null = null;
          let savedPassword: string | null = null;
          try {
            [savedEmail, savedPassword] = await Promise.all([
              invoke<string | null>("load_credential", { key: SAVED_EMAIL_KEY }),
              invoke<string | null>("load_credential", { key: SAVED_PASSWORD_KEY }),
            ]);
          } catch {
            // Corrupt keyring — clear and fall through
          }

          if (!savedEmail || !savedPassword) {
            // Invalid saved credentials — clear them, keep existing token if any
            get().clearSavedCredentials();
            if (!token) {
              set({ isAuthenticated: false, token: null });
            }
            return;
          }

          // Step 4: Attempt auto-login (only if token was missing or we want a fresh one)
          set({ rememberMe: true });
          try {
            const response = await api.login(savedEmail, savedPassword);

            if (response.requires_2fa && response.temp_token) {
              // 2FA required — show 2FA screen directly (credentials stay saved)
              // Only downgrade auth if we don't already have a working token
              if (!token) {
                set({
                  pendingTwoFactor: { tempToken: response.temp_token, email: savedEmail },
                  isAuthenticated: false,
                  token: null,
                });
              } else {
                set({ pendingTwoFactor: { tempToken: response.temp_token, email: savedEmail } });
              }
              return;
            }

            // Login success — store new token
            const newToken = response.token;
            await invoke("store_credential", { key: CREDENTIAL_KEY, value: newToken }).catch(() => {});
            const userWithRole: User = {
              id: response.user_id,
              email: savedEmail,
              name: savedEmail.split("@")[0],
              role: response.role,
              is_active: true,
              created_at: new Date().toISOString(),
            };
            set({ token: newToken, isAuthenticated: true, user: userWithRole });
          } catch (err) {
            if (isNetworkError(err)) {
              // Network error — DON'T clear credentials (transient issue).
              console.log("[Auth] Auto-login failed (network) — keeping credentials for next attempt");
              if (token) {
                set({ token, isAuthenticated: true });
              } else {
                set({ isAuthenticated: false, token: null });
              }
            } else {
              // Auth error (wrong password, account disabled etc.) — clear saved credentials
              // but PRESERVE existing token if we have one from keyring
              console.log("[Auth] Auto-login failed (auth error) — clearing saved credentials");
              get().clearSavedCredentials();
              if (token) {
                // Keep the keyring token — it was loaded successfully
                set({ rememberMe: false });
              } else {
                set({ isAuthenticated: false, token: null, rememberMe: false });
              }
            }
          }
        } catch {
          // Keyring completely unavailable — token stays null
        } finally {
          set({ isInitializing: false });
        }
      },
    }),
    {
      name: "auth-store",
      // Persist user info, auth flag + rememberMe to localStorage — token goes to keyring.
      // isAuthenticated is persisted so the UI doesn't flash to login during keyring load.
      partialize: (state) => ({ user: state.user, rememberMe: state.rememberMe, savedEmail: state.savedEmail, isAuthenticated: state.isAuthenticated }),
      onRehydrateStorage: () => (state) => {
        // After rehydration, load token from keyring (+ auto-login if remember me)
        if (state) {
          state.loadTokenFromKeyring();
        }
      },
    }
  )
);
