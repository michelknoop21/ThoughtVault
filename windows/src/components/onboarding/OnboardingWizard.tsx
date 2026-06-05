import { useState } from "react";
import {
  MicRecord24Regular,
  Server24Regular,
  Calendar24Regular,
  Checkmark24Regular,
  Person24Regular,
  ArrowRight24Regular,
  ArrowLeft24Regular,
} from "@fluentui/react-icons";
import { useSettingsStore } from "../../stores/settingsStore";
import { usePersonProfileStore } from "../../stores/personProfileStore";
import { MicrosoftGraphService } from "../../services/microsoftGraph";
import { YingaBar } from "../brand/YingaBar";
import { YingaFooter } from "../brand/YingaFooter";
import appLogo from "../../assets/app-logo.png";

type Step = 0 | 1 | 2 | 3 | 4 | 5;

const STEPS = ["Welkom", "Server", "Microfoon", "Agenda", "Profiel", "Klaar"];

export function OnboardingWizard() {
  const [step, setStep] = useState<Step>(0);
  const [serverUrl, setServerUrl] = useState("https://n8n.prezent.nl/tstudio/api");
  const settings = useSettingsStore();

  // Step 4 (Profiel) local state
  const [profileName, setProfileName] = useState("");
  const [profileRole, setProfileRole] = useState("");
  const [profileOrganization, setProfileOrganization] = useState("");
  const [profileAliases, setProfileAliases] = useState("");
  const [profileMeetingTypes, setProfileMeetingTypes] = useState("");
  const [profileExpertiseTags, setProfileExpertiseTags] = useState("");

  function handleNext() {
    if (step < 5) setStep((s) => (s + 1) as Step);
  }

  function handleBack() {
    if (step > 0) setStep((s) => (s - 1) as Step);
  }

  function handleComplete() {
    settings.updateSettings({ server_url: serverUrl });
    // Write profile only if at least one field is non-empty (D-07: skip writes nothing)
    const hasAnyField =
      profileName.trim() ||
      profileRole.trim() ||
      profileOrganization.trim() ||
      profileAliases.trim() ||
      profileMeetingTypes.trim() ||
      profileExpertiseTags.trim();

    if (hasAnyField) {
      const splitTrim = (s: string) =>
        s
          .split(",")
          .map((v) => v.trim())
          .filter(Boolean);
      usePersonProfileStore.getState().upsertProfile({
        name: profileName.trim(),
        role: profileRole.trim(),
        organization: profileOrganization.trim(),
        aliases: splitTrim(profileAliases),
        meetingTypes: splitTrim(profileMeetingTypes),
        expertiseTags: splitTrim(profileExpertiseTags),
      });
    }
    settings.setHasCompletedOnboarding(true);
  }

  async function handleConnectCalendar() {
    try {
      await MicrosoftGraphService.initiateAuth();
      handleNext();
    } catch {
      handleNext(); // Skip on error
    }
  }

  return (
    <div
      style={{
        flex: 1,
        minHeight: 0,
        display: "flex",
        flexDirection: "column",
        background: "var(--bg-solid-tertiary)",
      }}
    >
      <YingaBar />
      <div style={{ flex: 1, display: "flex", alignItems: "center", justifyContent: "center", minHeight: 0, overflowY: "auto" }}>
      <div style={{ width: "100%", maxWidth: 440, padding: 32 }}>
        {/* Progress dots */}
        <div style={{ display: "flex", alignItems: "center", justifyContent: "center", gap: 6, marginBottom: 32 }}>
          {STEPS.map((_, i) => (
            <div
              key={i}
              style={{
                height: 6,
                borderRadius: 3,
                background: i <= step ? "var(--fill-accent-default)" : "var(--stroke-divider)",
                width: i === step ? 24 : 6,
                transition: "width 200ms ease, background 200ms ease",
              }}
            />
          ))}
        </div>

        {/* Step content */}
        <div style={{ display: "flex", flexDirection: "column", gap: 16 }}>
          {step === 0 && (
            <StepContent
              icon={
                <img
                  src={appLogo}
                  alt="Transcript Studio"
                  style={{
                    width: 64,
                    height: 64,
                    borderRadius: 16,
                    margin: "0 auto 16px",
                    display: "block",
                    boxShadow: "0 2px 8px rgba(0,0,0,0.12)",
                  }}
                />
              }
              title="Welkom bij Transcript Studio"
              description="Neem vergaderingen op, genereer automatisch notulen en sla alles overzichtelijk op. Laten we uw setup in orde maken."
            />
          )}

          {step === 1 && (
            <StepContent
              icon={<StepIcon icon={<Server24Regular style={{ fontSize: 28 }} />} />}
              title="Server configuratie"
              description="Voer het adres in van uw TranscriptStudio server."
            >
              <div style={{ display: "flex", flexDirection: "column", gap: 4 }}>
                <label style={{ fontSize: 13, fontWeight: 500, color: "var(--text-secondary)" }}>
                  Server URL
                </label>
                <input
                  type="url"
                  value={serverUrl}
                  onChange={(e) => setServerUrl(e.target.value)}
                  placeholder="https://n8n.prezent.nl/tstudio/api"
                  style={{
                    width: "100%",
                    padding: "7px 10px",
                    background: "var(--fill-control-default)",
                    border: "1px solid var(--stroke-control-secondary)",
                    borderBottom: "1px solid var(--stroke-control-default)",
                    borderRadius: "var(--radius-sm)",
                    color: "var(--text-primary)",
                    fontSize: 13,
                    outline: "none",
                    fontFamily: "inherit",
                    boxSizing: "border-box",
                  }}
                />
              </div>
            </StepContent>
          )}

          {step === 2 && (
            <StepContent
              icon={<StepIcon icon={<MicRecord24Regular style={{ fontSize: 28 }} />} />}
              title="Microfoon toegang"
              description="TranscriptStudio heeft toegang nodig tot uw microfoon voor het opnemen van vergaderingen."
            >
              <div
                style={{
                  padding: "12px 14px",
                  background: "rgba(0, 95, 184, 0.06)",
                  border: "1px solid rgba(0, 95, 184, 0.20)",
                  borderRadius: "var(--radius-md)",
                }}
              >
                <p style={{ fontSize: 13, color: "var(--fill-system-attention)", lineHeight: 1.5 }}>
                  <strong>Windows privacy-instellingen:</strong> Zorg dat microfoon toegang is ingeschakeld via{" "}
                  <em>Instellingen → Privacy → Microfoon</em>.
                </p>
              </div>
            </StepContent>
          )}

          {step === 3 && (
            <StepContent
              icon={<StepIcon icon={<Calendar24Regular style={{ fontSize: 28 }} />} />}
              title="Agenda integratie"
              description={
                settings.ms365_client_id
                  ? "Verbind uw Microsoft 365 agenda om aankomende vergaderingen te zien. Dit is optioneel."
                  : "Agenda-koppeling is nog niet geconfigureerd door de beheerder. U kunt dit later instellen via Instellingen."
              }
            >
              <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
                {settings.ms365_client_id ? (
                  <button
                    onClick={handleConnectCalendar}
                    className="btn btn-accent"
                    style={{ width: "100%", padding: "9px 16px", fontSize: 14 }}
                  >
                    Verbinden met Microsoft 365
                  </button>
                ) : null}
                <button
                  onClick={handleNext}
                  className="btn btn-ghost"
                  style={{ width: "100%", fontSize: 13 }}
                >
                  {settings.ms365_client_id ? "Overslaan" : "Volgende"}
                </button>
              </div>
            </StepContent>
          )}

          {step === 4 && (
            <StepContent
              icon={<StepIcon icon={<Person24Regular style={{ fontSize: 28 }} />} />}
              title="Vertel iets over jezelf"
              description="TranscriptStudio gebruikt jouw profiel om actiepunten straks aan de juiste persoon te koppelen. Je kunt dit altijd later aanpassen."
            >
              <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
                <ProfileField
                  label="Naam"
                  value={profileName}
                  onChange={setProfileName}
                  placeholder="Voornaam Achternaam"
                />
                <ProfileField
                  label="Rol / Functie"
                  value={profileRole}
                  onChange={setProfileRole}
                  placeholder="Product Manager"
                />
                <ProfileField
                  label="Organisatie"
                  value={profileOrganization}
                  onChange={setProfileOrganization}
                  placeholder="Bedrijfsnaam"
                />
                <ProfileField
                  label="Hoe noemen collega's jou?"
                  value={profileAliases}
                  onChange={setProfileAliases}
                  placeholder="Michel, Knoop, MK (kommagescheiden)"
                />
                <ProfileField
                  label="Typische vergadertypen"
                  value={profileMeetingTypes}
                  onChange={setProfileMeetingTypes}
                  placeholder="Wekelijks overleg, Klantgesprek (kommagescheiden)"
                />
                <ProfileField
                  label="Expertise / onderwerpen"
                  value={profileExpertiseTags}
                  onChange={setProfileExpertiseTags}
                  placeholder="grafisch ontwerp, marketing, IT (kommagescheiden)"
                />
              </div>
            </StepContent>
          )}

          {step === 5 && (
            <StepContent
              icon={
                <div
                  style={{
                    width: 64,
                    height: 64,
                    background: "rgba(15, 123, 15, 0.10)",
                    borderRadius: "50%",
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                    margin: "0 auto 16px",
                  }}
                >
                  <Checkmark24Regular style={{ fontSize: 32, color: "var(--fill-system-success)" }} />
                </div>
              }
              title="U bent klaar!"
              description="TranscriptStudio is geconfigureerd en klaar voor gebruik. Start uw eerste opname."
            />
          )}
        </div>

        {/* Navigation */}
        <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginTop: 32 }}>
          {step > 0 ? (
            <button
              onClick={handleBack}
              className="btn btn-ghost"
              style={{ fontSize: 13, gap: 6 }}
            >
              <ArrowLeft24Regular style={{ fontSize: 15 }} />
              Vorige
            </button>
          ) : (
            <div />
          )}

          {step < 5 ? (
            <button
              onClick={handleNext}
              className="btn btn-accent"
              style={{ padding: "8px 20px", gap: 6 }}
            >
              {step === 3 || step === 4 ? "Overslaan" : "Volgende"}
              <ArrowRight24Regular style={{ fontSize: 16 }} />
            </button>
          ) : (
            <button
              onClick={handleComplete}
              className="btn btn-accent"
              style={{ padding: "8px 20px", gap: 6 }}
            >
              Beginnen
              <ArrowRight24Regular style={{ fontSize: 16 }} />
            </button>
          )}
        </div>

      </div>
      </div>
      <div style={{ marginTop: "auto", flexShrink: 0 }}>
        <YingaFooter />
      </div>
    </div>
  );
}

function ProfileField({
  label,
  value,
  onChange,
  placeholder,
}: {
  label: string;
  value: string;
  onChange: (v: string) => void;
  placeholder?: string;
}) {
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 4 }}>
      <label style={{ fontSize: 13, fontWeight: 500, color: "var(--text-secondary)" }}>
        {label}
      </label>
      <input
        type="text"
        value={value}
        onChange={(e) => onChange(e.target.value)}
        placeholder={placeholder}
        style={{
          width: "100%",
          padding: "7px 10px",
          background: "var(--fill-control-default)",
          border: "1px solid var(--stroke-control-secondary)",
          borderBottom: "1px solid var(--stroke-control-default)",
          borderRadius: "var(--radius-sm)",
          color: "var(--text-primary)",
          fontSize: 13,
          outline: "none",
          fontFamily: "inherit",
          boxSizing: "border-box",
        }}
      />
    </div>
  );
}

function StepIcon({ icon }: { icon: React.ReactNode }) {
  return (
    <div
      style={{
        width: 64,
        height: 64,
        background: "rgba(229, 0, 116, 0.08)",
        borderRadius: 16,
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        margin: "0 auto 16px",
        color: "var(--fill-accent-default)",
      }}
    >
      {icon}
    </div>
  );
}

function StepContent({
  icon,
  title,
  description,
  children,
}: {
  icon: React.ReactNode;
  title: string;
  description: string;
  children?: React.ReactNode;
}) {
  return (
    <div>
      {icon}
      <h2 style={{ fontSize: 20, fontWeight: 600, color: "var(--text-primary)", textAlign: "center", margin: 0 }}>
        {title}
      </h2>
      <p style={{ fontSize: 13, color: "var(--text-tertiary)", textAlign: "center", marginTop: 8, marginBottom: 20, lineHeight: 1.6 }}>
        {description}
      </p>
      {children}
    </div>
  );
}
