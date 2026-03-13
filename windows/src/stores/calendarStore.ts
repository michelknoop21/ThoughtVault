import { create } from "zustand";
import { persist } from "zustand/middleware";
import type { CalendarEvent } from "../types";

interface CalendarState {
  isConnected: boolean;
  accountEmail: string | null;
  accessToken: string | null;
  refreshToken: string | null;
  tokenExpiry: number | null;
  events: CalendarEvent[];
  lastSync: string | null;
  setConnected: (email: string, accessToken: string, refreshToken: string, expiry: number) => void;
  setEvents: (events: CalendarEvent[]) => void;
  setLastSync: (timestamp: string) => void;
  disconnect: () => void;
  updateTokens: (accessToken: string, expiry: number) => void;
}

export const useCalendarStore = create<CalendarState>()(
  persist(
    (set) => ({
      isConnected: false,
      accountEmail: null,
      accessToken: null,
      refreshToken: null,
      tokenExpiry: null,
      events: [],
      lastSync: null,
      setConnected: (email, accessToken, refreshToken, expiry) =>
        set({
          isConnected: true,
          accountEmail: email,
          accessToken,
          refreshToken,
          tokenExpiry: expiry,
        }),
      setEvents: (events) => set({ events }),
      setLastSync: (timestamp) => set({ lastSync: timestamp }),
      disconnect: () =>
        set({
          isConnected: false,
          accountEmail: null,
          accessToken: null,
          refreshToken: null,
          tokenExpiry: null,
          events: [],
          lastSync: null,
        }),
      updateTokens: (accessToken, expiry) =>
        set({ accessToken, tokenExpiry: expiry }),
    }),
    {
      name: "calendar-store",
      partialize: (state) => ({
        isConnected: state.isConnected,
        accountEmail: state.accountEmail,
        refreshToken: state.refreshToken,
        tokenExpiry: state.tokenExpiry,
      }),
    }
  )
);
