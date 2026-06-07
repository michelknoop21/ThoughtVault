// Test setup — runs before each test file.
// Provides a functional localStorage mock for zustand persist middleware
// in the jsdom environment, which requires a URL to enable localStorage.

// Vitest jsdom may not have localStorage.setItem when the store module is
// first imported (before the test environment URL is set). We patch the global
// with a Map-backed implementation so zustand persist can capture it at import time.
const store = new Map<string, string>();

Object.defineProperty(global, "localStorage", {
  value: {
    getItem: (key: string) => store.get(key) ?? null,
    setItem: (key: string, value: string) => { store.set(key, value); },
    removeItem: (key: string) => { store.delete(key); },
    clear: () => { store.clear(); },
    get length() { return store.size; },
    key: (index: number) => [...store.keys()][index] ?? null,
  },
  writable: true,
});
