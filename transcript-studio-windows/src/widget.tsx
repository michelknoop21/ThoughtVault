import React from "react";
import ReactDOM from "react-dom/client";
import { RecordingWidget } from "./components/recording/RecordingWidget";
import "./styles/widget.css";

ReactDOM.createRoot(document.getElementById("widget-root")!).render(
  <React.StrictMode>
    <RecordingWidget />
  </React.StrictMode>
);
