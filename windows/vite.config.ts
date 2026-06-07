import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import { resolve } from "path";

const host = process.env.TAURI_DEV_HOST;

export default defineConfig(async () => ({
  plugins: [react()],
  clearScreen: false,

  // Vitest configuration — jsdom with localStorage mock for zustand persist stores
  test: {
    environment: "jsdom",
    globals: true,
    // setupFiles runs before module imports, ensuring localStorage is available
    // when the zustand persist middleware captures the storage reference
    setupFiles: ["./src/test-setup.ts"],
  },

  // Multi-page: main app + floating recording widget
  build: {
    rollupOptions: {
      input: {
        main:   resolve(__dirname, "index.html"),
        widget: resolve(__dirname, "widget.html"),
      },
    },
  },

  server: {
    port: 1420,
    strictPort: true,
    host: host || false,
    hmr: host
      ? { protocol: "ws", host, port: 1421 }
      : undefined,
    watch: {
      ignored: ["**/src-tauri/**", "**/vite.config.ts"],
    },
  },
}));
