import React from "react";
import { initCrashReporter } from "./services/localCrashReporter";
import ReactDOM from "react-dom/client";
import { RecordingWidget } from "./components/recording/RecordingWidget";
import "./styles/widget.css";
import { installClickPath, installConsoleForwarding } from "./services/appLog";

initCrashReporter();
installConsoleForwarding();
installClickPath();

ReactDOM.createRoot(document.getElementById("widget-root")!).render(
  <React.StrictMode>
    <RecordingWidget />
  </React.StrictMode>
);
