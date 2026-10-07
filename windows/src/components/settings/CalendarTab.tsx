import { useState } from "react";
import { Calendar24Regular } from "@fluentui/react-icons";
import { useSettingsStore } from "../../stores/settingsStore";
import { CardHead } from "./SettingsFields";
import { useCalendarStore } from "../../stores/calendarStore";
import { MicrosoftGraphService } from "../../services/microsoftGraph";

export function CalendarTab() {
  const settings = useSettingsStore();
  const calendar = useCalendarStore();
  const [isConnecting, setIsConnecting] = useState(false);
  const hasOAuthConfig = Boolean(settings.ms365_client_id && settings.ms365_tenant_id);

  async function handleConnect365() {
    setIsConnecting(true);
    try {
      await MicrosoftGraphService.initiateAuth();
    } catch (err) {
      console.error("Auth failed:", err);
    } finally {
      setIsConnecting(false);
    }
  }
  return <div className="settings-other"><header className="settings-section-header"><div><h2>Agenda</h2><p>Verbind je agenda met ThoughtVault.</p></div></header>          {/* Agenda */}
          <div className="settings-group">
            <CardHead icon={<Calendar24Regular />} title="Agenda" subtitle="Je agenda in ThoughtVault" />
            {calendar.isConnected ? (
              <>
                <div className="settings-row">
                  <div className="flex-row gap-10 flex-1">
                    <Calendar24Regular className="settings-icon" style={{ color: "var(--fill-system-success)" }} />
                    <div className="flex-1">
                      <p className="settings-label">Microsoft 365</p>
                      <p className="settings-desc-success">
                        Verbonden: {calendar.accountEmail}
                      </p>
                    </div>
                  </div>
                </div>
                <div style={{ padding: "0 14px 12px" }}>
                  <button
                    onClick={() => calendar.disconnect()}
                    className="btn btn-secondary btn-sm"
                  >
                    Verbinding verbreken
                  </button>
                </div>
              </>
            ) : hasOAuthConfig ? (
              <>
                <div className="settings-row">
                  <div className="flex-row gap-10 flex-1">
                    <Calendar24Regular className="settings-icon-muted" />
                    <div className="flex-1">
                      <p className="settings-label">Microsoft 365</p>
                      <p className="settings-desc">Niet verbonden</p>
                    </div>
                  </div>
                </div>
                <div style={{ padding: "0 14px 12px" }}>
                  <button
                    onClick={handleConnect365}
                    disabled={isConnecting}
                    className="btn btn-accent btn-sm"
                  >
                    {isConnecting ? "Verbinden..." : "Verbinden met Microsoft 365"}
                  </button>
                </div>
              </>
            ) : (
              <div className="settings-row">
                <div className="flex-row gap-10 flex-1">
                  <Calendar24Regular className="settings-icon-muted" />
                  <div className="flex-1">
                    <p className="settings-label">Microsoft 365</p>
                    <p className="settings-desc">
                      Agenda-koppeling niet geconfigureerd. Neem contact op met de beheerder.
                    </p>
                  </div>
                </div>
              </div>
            )}
          </div>

</div>;
}
