import { useState } from "react";
import { useNavigate } from "react-router-dom";
import {
  MicRecord24Regular,
  Checkmark24Regular,
  Person24Regular,
  ArrowRight24Regular,
  ArrowLeft24Regular,
} from "@fluentui/react-icons";
import { useSettingsStore } from "../../stores/settingsStore";
import { usePersonProfileStore } from "../../stores/personProfileStore";
import { LocalModelSetup } from "../settings/LocalModelSetup";
import { BrandBar } from "../brand/BrandBar";
import { BrandFooter } from "../brand/BrandFooter";
import appLogo from "../../assets/app-logo.png";

type Step = 0 | 1 | 2 | 3 | 4;

const STEPS = ["Welkom", "Lokale modellen", "Microfoon", "Profiel", "Klaar"];

export function OnboardingWizard() {
  const [step, setStep] = useState<Step>(0);
  const settings = useSettingsStore();
  const navigate = useNavigate();

  // Step 4 (Profiel) local state
  const [profileName, setProfileName] = useState("");
  const [profileRole, setProfileRole] = useState("");
  const [profileOrganization, setProfileOrganization] = useState("");
  const [profileAliases, setProfileAliases] = useState("");
  const [profileMeetingTypes, setProfileMeetingTypes] = useState("");
  const [profileExpertiseTags, setProfileExpertiseTags] = useState("");

  function handleNext() {
    if (step < 4) setStep((s) => (s + 1) as Step);
  }

  function handleBack() {
    if (step > 0) setStep((s) => (s - 1) as Step);
  }

  function handleComplete() {
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
    // Land on the recording screen so the first action is one tap away.
    navigate("/recording");
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
      <BrandBar />
      <div style={{ flex: 1, display: "flex", alignItems: "flex-start", justifyContent: "center", minHeight: 0, overflowY: "auto" }}>
      <div style={{ width: "100%", maxWidth: 760, padding: "32px 32px 64px", margin: "auto 0" }}>
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
                transition: "background 200ms ease",
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
                  alt="ThoughtVault"
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
              title="Welkom bij ThoughtVault"
              description="Neem vergaderingen op, genereer automatisch notulen en sla alles overzichtelijk op. Laten we je setup in orde maken."
            />
          )}

          {step === 1 && (
            <StepContent title="Lokale modellen" description="Richt transcriptie en notulen in op je eigen pc.">
              <LocalModelSetup />
            </StepContent>
          )}

          {step === 2 && (
            <StepContent
              icon={<StepIcon icon={<MicRecord24Regular style={{ fontSize: 28 }} />} />}
              title="Microfoon toegang"
              description="ThoughtVault heeft toegang nodig tot je microfoon voor het opnemen van vergaderingen."
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
              icon={<StepIcon icon={<Person24Regular style={{ fontSize: 28 }} />} />}
              title="Vertel iets over jezelf"
              description="ThoughtVault gebruikt jouw profiel om actiepunten straks aan de juiste persoon te koppelen. Je kunt dit altijd later aanpassen."
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

          {step === 4 && (
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
              title="Je bent klaar!"
              description="Start een korte testopname. Als je modellen nog ontbreken, kun je die later via Instellingen installeren."
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

          {step < 4 ? (
            <button
              onClick={handleNext}
              className="btn btn-accent"
              style={{ padding: "8px 20px", gap: 6 }}
            >
              {step === 1 || step === 3 ? "Overslaan" : "Volgende"}
              <ArrowRight24Regular style={{ fontSize: 16 }} />
            </button>
          ) : (
            <button
              onClick={handleComplete}
              className="btn btn-accent"
              style={{ padding: "8px 20px", gap: 6 }}
            >
              Maak je eerste opname
              <ArrowRight24Regular style={{ fontSize: 16 }} />
            </button>
          )}
        </div>

      </div>
      </div>
      <div style={{ marginTop: "auto", flexShrink: 0 }}>
        <BrandFooter />
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
        background: "rgba(144, 72, 240, 0.08)",
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
  icon?: React.ReactNode;
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
