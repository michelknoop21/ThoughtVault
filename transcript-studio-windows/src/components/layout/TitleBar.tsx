import { getCurrentWindow } from "@tauri-apps/api/window";
import {
  Dismiss20Regular,
  Subtract20Regular,
  SquareMultiple20Regular,
} from "@fluentui/react-icons";
import { useState } from "react";

export function TitleBar() {
  const [isMaximized, setIsMaximized] = useState(false);

  async function handleMinimize() {
    const win = getCurrentWindow();
    await win.minimize();
  }

  async function handleMaximize() {
    const win = getCurrentWindow();
    const maximized = await win.isMaximized();
    if (maximized) {
      await win.unmaximize();
      setIsMaximized(false);
    } else {
      await win.maximize();
      setIsMaximized(true);
    }
  }

  async function handleClose() {
    const win = getCurrentWindow();
    await win.close();
  }

  return (
    <div style={{ flexShrink: 0 }}>
      {/* 32px drag region with window controls */}
      <div
        data-tauri-drag-region
        style={{
          height: 32,
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
          background: "transparent",
          userSelect: "none",
        }}
      >
        {/* Drag area — covers everything except window controls */}
        <div data-tauri-drag-region style={{ flex: 1, paddingLeft: 12, display: "flex", alignItems: "center" }}>
          <span style={{ fontSize: 12, color: "var(--text-secondary)", fontWeight: 500 }}>
            TranscriptStudio
          </span>
        </div>

        {/* Window controls — 46px wide each (Windows standard) */}
        <div style={{ display: "flex", height: "100%" }}>
          <button
            onClick={handleMinimize}
            style={{
              width: 46,
              height: "100%",
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              background: "transparent",
              border: "none",
              color: "var(--text-secondary)",
              cursor: "default",
            }}
            className="win-control"
            title="Minimaliseren"
          >
            <Subtract20Regular style={{ fontSize: 16 }} />
          </button>
          <button
            onClick={handleMaximize}
            style={{
              width: 46,
              height: "100%",
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              background: "transparent",
              border: "none",
              color: "var(--text-secondary)",
              cursor: "default",
            }}
            className="win-control"
            title={isMaximized ? "Herstellen" : "Maximaliseren"}
          >
            <SquareMultiple20Regular style={{ fontSize: 16 }} />
          </button>
          <button
            onClick={handleClose}
            style={{
              width: 46,
              height: "100%",
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              background: "transparent",
              border: "none",
              color: "var(--text-secondary)",
              cursor: "default",
            }}
            className="win-control-close"
            title="Sluiten"
          >
            <Dismiss20Regular style={{ fontSize: 16 }} />
          </button>
        </div>
      </div>

      {/* Yinga brand bar — 3px gradient strip below title bar */}
      <div className="brand-bar" />
    </div>
  );
}
