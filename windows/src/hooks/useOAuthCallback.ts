import { useEffect } from "react";
import { listen } from "@tauri-apps/api/event";
import { MicrosoftGraphService } from "../services/microsoftGraph";

export function useOAuthCallback() {
  useEffect(() => {
    const unlisten = listen<string>("oauth-callback", async (event) => {
      try {
        await MicrosoftGraphService.handleAuthCallback(event.payload);
      } catch (err) {
        console.error("[OAuth] Callback verwerking mislukt:", err);
      }
    });

    return () => {
      unlisten.then((fn) => fn());
    };
  }, []);
}
