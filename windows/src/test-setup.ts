// Test setup — runs before each test file in the jsdom environment.
// Provides a functional localStorage implementation so zustand persist middleware
// can capture a working storage reference at module-import time (before tests run).
// jsdom's native localStorage requires a URL to be configured; this Map-backed
// implementation is always available, regardless of jsdom initialization order.

const store = new Map<string, string>();

const localStorageMock = {
  getItem: (key: string): string | null => store.get(key) ?? null,
  setItem: (key: string, value: string): void => { store.set(key, value); },
  removeItem: (key: string): void => { store.delete(key); },
  clear: (): void => { store.clear(); },
  get length(): number { return store.size; },
  key: (index: number): string | null => [...store.keys()][index] ?? null,
};

// Use window (jsdom context) not global (Node context)
Object.defineProperty(window, "localStorage", {
  value: localStorageMock,
  writable: true,
});

// jsdom has no top-layer dialog implementation. Browser QA checks real focus.
HTMLDialogElement.prototype.showModal = function () { this.setAttribute("open", ""); };
HTMLDialogElement.prototype.close = function () { this.removeAttribute("open"); };
