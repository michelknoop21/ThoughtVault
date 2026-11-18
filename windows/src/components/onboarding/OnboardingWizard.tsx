import { useEffect, useRef, useState } from "react";
import { useNavigate } from "react-router-dom";
import {
  MicRecord24Regular,
  Calendar24Regular,
  Checkmark24Regular,
  Person24Regular,
  ArrowRight24Regular,
  ArrowLeft24Regular,
} from "../ui/StudioIcons";
import { useSettingsStore } from "../../stores/settingsStore";
import { usePersonProfileStore } from "../../stores/personProfileStore";
import { MicrosoftGraphService } from "../../services/microsoftGraph";
import { BrandBar } from "../brand/BrandBar";
import { BrandFooter } from "../brand/BrandFooter";
import appLogo from "../../assets/app-logo.png";
import { NotulenStep } from "./NotulenStep";

type Step = 0 | 1 | 2 | 3 | 4 | 5;

const STEPS = ["Welkom", "Microfoon", "Agenda", "Notulen", "Profiel", "Klaar"];
const NOTULEN_STEP = 3;

export function OnboardingWizard() {
  const [step, setStep] = useState<Step>(0);
  const panel = useRef<HTMLDivElement>(null);
  const previousStep = useRef(step);
  useEffect(() => {
    if (previousStep.current === step) return;
    previousStep.current = step;
    panel.current?.querySelector("h1")?.focus();
  }, [step]);
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
    if (step < 5) setStep((s) => (s + 1) as Step);
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

  async function handleConnectCalendar() {
    try {
      await MicrosoftGraphService.initiateAuth();
      handleNext();
    } catch {
      handleNext(); // Skip on error
    }
  }

  return (
    <div className="onb-shell">
      <BrandBar />
      <div className="onb-scroll">
        <main className="onb-frame">
          <div className="onb-rail">
            <div className="onb-brand"><img src={appLogo} alt="" />ThoughtVault</div>
            <ol className="onb-stepper" aria-label={`Stap ${step + 1} van ${STEPS.length}`}>
              {STEPS.map((label, i) => (
                <li key={label} className={i < step ? "done" : i === step ? "current" : ""} aria-current={i === step ? "step" : undefined}>
                  <i aria-hidden="true">{i < step ? "✓" : i + 1}</i><span>{label}</span>
                </li>
              ))}
            </ol>
          </div>
          <div className="onb-panel" ref={panel}>
            <div key={step} className="onb-content">
              {step === 0 && (
                <StepContent
                  title="Welkom bij ThoughtVault"
                  description="Neem vergaderingen op, genereer automatisch notulen en sla alles overzichtelijk op."
                />
              )}

              {step === 1 && (
                <StepContent
                  icon={<StepIcon icon={<MicRecord24Regular style={{ fontSize: 28 }} />} />}
                  title="Microfoon instellen"
                  description="ThoughtVault heeft toegang nodig tot je microfoon voor het opnemen van vergaderingen."
                >
                  <p className="onb-note">
                    Zet microfoontoegang aan via <strong>Windows-instellingen › Privacy › Microfoon</strong>.
                  </p>
                </StepContent>
              )}

              {step === 2 && (
                <StepContent
                  icon={<StepIcon icon={<Calendar24Regular style={{ fontSize: 28 }} />} />}
                  title="Agenda verbinden"
                  description={
                    settings.ms365_client_id
                      ? "Verbind je Microsoft 365 agenda om aankomende vergaderingen te zien. Dit is optioneel."
                      : "Agenda-koppeling is nog niet geconfigureerd door de beheerder. Je kunt dit later instellen via Instellingen."
                  }
                >
                  {settings.ms365_client_id && (
                    <button onClick={handleConnectCalendar} className="btn btn-secondary">
                      Verbinden met Microsoft 365
                    </button>
                  )}
                </StepContent>
              )}

              {step === NOTULEN_STEP && <NotulenStep onBack={handleBack} onDone={handleNext} />}

              {step === 4 && (
                <StepContent
                  icon={<StepIcon icon={<Person24Regular style={{ fontSize: 28 }} />} />}
                  title="Vertel iets over jezelf"
                  description="ThoughtVault gebruikt jouw profiel om actiepunten straks aan de juiste persoon te koppelen. Je kunt dit altijd later aanpassen."
                >
                  <div className="onb-profile">
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
                      placeholder="Voornaam, bijnaam, initialen (kommagescheiden)"
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
                  icon={<StepIcon icon={<Checkmark24Regular />} />}
                  title="Je bent klaar!"
                  description="Start een korte testopname of neem direct je volgende vergadering op."
                />
              )}
            </div>

            {/* Navigation; the notulen step has its own footer */}
            {step !== NOTULEN_STEP && <div className="onb-footer">
              {step > 0 ? (
                <button
                  onClick={handleBack}
                  className="btn btn-ghost"
                >
                  <ArrowLeft24Regular style={{ fontSize: 15 }} />
                  Vorige
                </button>
              ) : null}
              <span className="onb-spacer" />

              {step < 5 ? (
                <button
                  onClick={handleNext}
                  className="btn btn-accent"
                >
                  {step === 2 && settings.ms365_client_id ? "Overslaan" : "Volgende"}
                  <ArrowRight24Regular style={{ fontSize: 16 }} />
                </button>
              ) : (
                <button
                  onClick={handleComplete}
                  className="btn btn-accent"
                >
                  Maak je eerste opname
                  <ArrowRight24Regular style={{ fontSize: 16 }} />
                </button>
              )}
            </div>}

          </div>
        </main>
      </div>
      <BrandFooter />
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
    <label className="onb-field">
      {label}
      <input className="input" type="text" value={value}
        onChange={event => onChange(event.target.value)} placeholder={placeholder} />
    </label>
  );
}

function StepIcon({ icon }: { icon: React.ReactNode }) {
  return <span className="onb-step-icon" aria-hidden="true">{icon}</span>;
}

function StepContent({ icon, title, description, children }: {
  icon?: React.ReactNode;
  title: string;
  description: string;
  children?: React.ReactNode;
}) {
  return (
    <>
      {icon}
      <h1 className="onb-title" tabIndex={-1}>{title}</h1>
      <p className="onb-lead">{description}</p>
      {children && <div className="onb-body">{children}</div>}
    </>
  );
}
