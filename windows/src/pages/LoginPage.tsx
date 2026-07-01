import { useState, useEffect } from "react";
import { useNavigate } from "react-router-dom";
import { api } from "../services/api";
import { useAuthStore } from "../stores/authStore";
import { useSettingsStore } from "../stores/settingsStore";
import { TitleBar } from "../components/layout/TitleBar";
import { YingaFooter } from "../components/brand/YingaFooter";
import appLogo from "../assets/app-logo.png";

function extractMessage(err: unknown): string {
  if (typeof err === "string") return err;
  if (err instanceof Error) return err.message;
  if (err && typeof err === "object") {
    const e = err as Record<string, unknown>;
    if (typeof e.message === "string") return e.message;
    if (typeof e.error === "string") return e.error;
  }
  return "Inloggen mislukt";
}

type LoginView = "login" | "2fa" | "reset-request" | "reset-verify" | "reset-complete";

export function LoginPage() {
  const navigate = useNavigate();
  const {
    setToken, setUser, isAuthenticated,
    rememberMe, setRememberMe, savedEmail, setSavedEmail,
    saveCredentials, clearSavedCredentials,
    pendingTwoFactor, clearPendingTwoFactor,
  } = useAuthStore();

  // Redirect to home if already authenticated (e.g. keyring loaded late)
  useEffect(() => {
    if (isAuthenticated) {
      navigate("/", { replace: true });
    }
  }, [isAuthenticated, navigate]);

  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [twoFactorCode, setTwoFactorCode] = useState("");
  const [tempToken, setTempToken] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [view, setView] = useState<LoginView>("login");

  // If auto-login detected 2FA, jump straight to the 2FA view
  useEffect(() => {
    if (pendingTwoFactor) {
      setEmail(pendingTwoFactor.email);
      setTempToken(pendingTwoFactor.tempToken);
      setView("2fa");
      clearPendingTwoFactor();
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Pre-fill email from remembered value (re-runs when zustand rehydrates)
  useEffect(() => {
    if (rememberMe && savedEmail) {
      setEmail(savedEmail);
    }
  }, [rememberMe, savedEmail]);

  const [resetEmail, setResetEmail] = useState("");
  const [resetCode, setResetCode] = useState("");
  const [resetToken, setResetToken] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [successMessage, setSuccessMessage] = useState<string | null>(null);

  async function handleLogin(e: React.FormEvent) {
    e.preventDefault();
    setIsLoading(true);
    setError(null);
    try {
      const response = await api.login(email, password);
      if (response.requires_2fa && response.temp_token) {
        setTempToken(response.temp_token);
        setView("2fa");
      } else {
        const userWithRole = {
          id: response.user_id,
          email: email,
          name: email.split("@")[0],
          role: response.role,
          is_active: true,
          created_at: new Date().toISOString(),
        };
        if (rememberMe) {
          setSavedEmail(email);
          await saveCredentials(email, password);
        }
        setToken(response.token);
        setUser(userWithRole);
        navigate("/", { replace: true });
      }
    } catch (err) {
      setError(extractMessage(err));
    } finally {
      setIsLoading(false);
    }
  }

  async function handle2FA(e: React.FormEvent) {
    e.preventDefault();
    if (!tempToken) return;
    setIsLoading(true);
    setError(null);
    try {
      const response = await api.verify2FA(email, tempToken, twoFactorCode);
      const userWithRole = {
        id: response.user_id,
        email: email,
        name: email.split("@")[0],
        role: response.role,
        is_active: true,
        created_at: new Date().toISOString(),
      };
      if (rememberMe) {
        setSavedEmail(email);
        await saveCredentials(email, password);
      }
      setToken(response.token);
      setUser(userWithRole);
      navigate("/", { replace: true });
    } catch (err) {
      setError(extractMessage(err));
    } finally {
      setIsLoading(false);
    }
  }

  async function handleResetRequest(e: React.FormEvent) {
    e.preventDefault();
    setIsLoading(true);
    setError(null);
    try {
      await api.requestPasswordReset(resetEmail);
      setView("reset-verify");
    } catch (err) {
      setError(extractMessage(err));
    } finally {
      setIsLoading(false);
    }
  }

  async function handleResetVerify(e: React.FormEvent) {
    e.preventDefault();
    setIsLoading(true);
    setError(null);
    try {
      const result = await api.verifyPasswordReset(resetEmail, resetCode);
      setResetToken(result.reset_token);
      setView("reset-complete");
    } catch (err) {
      setError(extractMessage(err));
    } finally {
      setIsLoading(false);
    }
  }

  async function handleResetComplete(e: React.FormEvent) {
    e.preventDefault();
    if (newPassword !== confirmPassword) {
      setError("Wachtwoorden komen niet overeen");
      return;
    }
    setIsLoading(true);
    setError(null);
    try {
      await api.completePasswordReset(resetToken, newPassword);
      setSuccessMessage("Wachtwoord succesvol gewijzigd. Je kunt nu inloggen.");
      setView("login");
      setResetEmail("");
      setResetCode("");
      setResetToken("");
      setNewPassword("");
      setConfirmPassword("");
    } catch (err) {
      setError(extractMessage(err));
    } finally {
      setIsLoading(false);
    }
  }

  function backToLogin() {
    setView("login");
    setError(null);
    setSuccessMessage(null);
    setTempToken(null);
    setTwoFactorCode("");
    setResetEmail("");
    setResetCode("");
    clearPendingTwoFactor();
  }

  return (
    <div className="app-shell">
      {/* Title bar with window controls and YingaBar */}
      <TitleBar />

      <div className="login-container">
        <div className="login-content">
          {/* Branding header — matches macOS LoginView */}
          <div className="text-center" style={{ marginBottom: 32 }}>
            <img
              src={appLogo}
              alt="TranscriptStudio"
              className="login-logo"
            />
            <h1 className="text-accent login-title">Transcript Studio</h1>
          </div>

          {/* Success message */}
          {successMessage && (
            <div className="error-banner" style={{ background: "var(--accent-bg-accent)", color: "var(--text-success)", borderColor: "var(--status-success)" }}>
              {successMessage}
            </div>
          )}

          {/* Error */}
          {error && (
            <div className="error-banner">
              {error}
            </div>
          )}

          {/* Form */}
          <div className="card-elevated login-card">
            {view === "login" && (
              <form onSubmit={handleLogin} className="login-form">
                <FormField label="E-mailadres">
                  <input
                    type="email"
                    value={email}
                    onChange={(e) => setEmail(e.target.value)}
                    required
                    autoFocus
                    placeholder="naam@bedrijf.nl"
                    className="input"
                  />
                </FormField>

                <FormField label="Wachtwoord">
                  <input
                    type="password"
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                    required
                    placeholder="••••••••"
                    className="input"
                  />
                </FormField>

                <label className="form-checkbox">
                  <input
                    type="checkbox"
                    checked={rememberMe}
                    onChange={(e) => {
                      setRememberMe(e.target.checked);
                      if (!e.target.checked) {
                        setSavedEmail("");
                        clearSavedCredentials();
                      }
                    }}
                  />
                  Onthoud mij
                </label>

                <button
                  type="submit"
                  disabled={isLoading}
                  className="btn btn-accent login-btn"
                >
                  {isLoading ? "Inloggen..." : "Inloggen"}
                </button>

                <button
                  type="button"
                  onClick={() => { setView("reset-request"); setError(null); setSuccessMessage(null); }}
                  className="btn btn-ghost login-btn-back"
                >
                  Wachtwoord vergeten?
                </button>

                {/* Use the app fully locally, without the server (no account needed). */}
                <button
                  type="button"
                  onClick={() => {
                    useSettingsStore.getState().updateSettings({
                      processing_mode: "local",
                      has_completed_onboarding: true,
                    });
                    navigate("/", { replace: true });
                  }}
                  className="btn btn-ghost login-btn-back"
                >
                  Lokaal gebruiken (zonder server)
                </button>
              </form>
            )}

            {view === "2fa" && (
              <form onSubmit={handle2FA} className="login-form">
                <FormField label="Authenticatiecode">
                  <input
                    type="text"
                    value={twoFactorCode}
                    onChange={(e) => setTwoFactorCode(e.target.value.replace(/\D/g, ""))}
                    required
                    autoFocus
                    maxLength={6}
                    placeholder="000000"
                    className="input"
                    style={{
                      textAlign: "center",
                      fontSize: 24,
                      letterSpacing: "0.4em",
                      maxWidth: "100%",
                    }}
                  />
                </FormField>

                <button
                  type="submit"
                  disabled={isLoading || twoFactorCode.length !== 6}
                  className="btn btn-accent login-btn"
                >
                  {isLoading ? "Verifiëren..." : "Verifiëren"}
                </button>

                <button
                  type="button"
                  onClick={backToLogin}
                  className="btn btn-ghost login-btn-back"
                >
                  Terug naar inloggen
                </button>
              </form>
            )}

            {view === "reset-request" && (
              <form onSubmit={handleResetRequest} className="login-form">
                <p className="text-caption" style={{ marginBottom: 8, color: "var(--text-secondary)" }}>
                  Voer je e-mailadres in. Je ontvangt een verificatiecode om je wachtwoord te resetten.
                </p>
                <FormField label="E-mailadres">
                  <input
                    type="email"
                    value={resetEmail}
                    onChange={(e) => setResetEmail(e.target.value)}
                    required
                    autoFocus
                    placeholder="naam@bedrijf.nl"
                    className="input"
                  />
                </FormField>

                <button
                  type="submit"
                  disabled={isLoading}
                  className="btn btn-accent login-btn"
                >
                  {isLoading ? "Versturen..." : "Code versturen"}
                </button>

                <button
                  type="button"
                  onClick={backToLogin}
                  className="btn btn-ghost login-btn-back"
                >
                  Terug naar inloggen
                </button>
              </form>
            )}

            {view === "reset-verify" && (
              <form onSubmit={handleResetVerify} className="login-form">
                <p className="text-caption" style={{ marginBottom: 8, color: "var(--text-secondary)" }}>
                  Voer de verificatiecode in die naar {resetEmail} is gestuurd.
                </p>
                <FormField label="Verificatiecode">
                  <input
                    type="text"
                    value={resetCode}
                    onChange={(e) => setResetCode(e.target.value.replace(/\D/g, ""))}
                    required
                    autoFocus
                    maxLength={6}
                    placeholder="000000"
                    className="input"
                    style={{
                      textAlign: "center",
                      fontSize: 24,
                      letterSpacing: "0.4em",
                    }}
                  />
                </FormField>

                <button
                  type="submit"
                  disabled={isLoading || resetCode.length < 4}
                  className="btn btn-accent login-btn"
                >
                  {isLoading ? "Verifiëren..." : "Verifiëren"}
                </button>

                <button
                  type="button"
                  onClick={backToLogin}
                  className="btn btn-ghost login-btn-back"
                >
                  Terug naar inloggen
                </button>
              </form>
            )}

            {view === "reset-complete" && (
              <form onSubmit={handleResetComplete} className="login-form">
                <FormField label="Nieuw wachtwoord">
                  <input
                    type="password"
                    value={newPassword}
                    onChange={(e) => setNewPassword(e.target.value)}
                    required
                    autoFocus
                    placeholder="••••••••"
                    className="input"
                  />
                </FormField>

                <FormField label="Bevestig wachtwoord">
                  <input
                    type="password"
                    value={confirmPassword}
                    onChange={(e) => setConfirmPassword(e.target.value)}
                    required
                    placeholder="••••••••"
                    className="input"
                  />
                </FormField>

                <button
                  type="submit"
                  disabled={isLoading || !newPassword || !confirmPassword}
                  className="btn btn-accent login-btn"
                >
                  {isLoading ? "Opslaan..." : "Wachtwoord opslaan"}
                </button>

                <button
                  type="button"
                  onClick={backToLogin}
                  className="btn btn-ghost login-btn-back"
                >
                  Terug naar inloggen
                </button>
              </form>
            )}
          </div>

        </div>
      </div>
      <YingaFooter />
    </div>
  );
}

function FormField({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="form-field">
      <label className="form-label">{label}</label>
      {children}
    </div>
  );
}
