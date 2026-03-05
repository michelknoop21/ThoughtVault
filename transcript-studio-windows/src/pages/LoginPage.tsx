import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { api } from "../services/api";
import { useAuthStore } from "../stores/authStore";
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

export function LoginPage() {
  const navigate = useNavigate();
  const { setToken, setUser } = useAuthStore();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [twoFactorCode, setTwoFactorCode] = useState("");
  const [tempToken, setTempToken] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleLogin(e: React.FormEvent) {
    e.preventDefault();
    setIsLoading(true);
    setError(null);
    try {
      const response = await api.login(email, password);
      if (response.requires_2fa && response.temp_token) {
        setTempToken(response.temp_token);
      } else {
        // Decode role from JWT if not in response
        const userWithRole = response.user ?? decodeUserFromToken(response.token);
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
      const userWithRole = response.user ?? decodeUserFromToken(response.token);
      setToken(response.token);
      setUser(userWithRole);
      navigate("/", { replace: true });
    } catch (err) {
      setError(extractMessage(err));
    } finally {
      setIsLoading(false);
    }
  }

  return (
    <div className="page-scroll">
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

          {/* Error */}
          {error && (
            <div className="error-banner">
              {error}
            </div>
          )}

          {/* Form */}
          <div className="card-elevated login-card">
            {!tempToken ? (
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

                <button
                  type="submit"
                  disabled={isLoading}
                  className="btn btn-accent login-btn"
                >
                  {isLoading ? "Inloggen..." : "Inloggen"}
                </button>
              </form>
            ) : (
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
                  onClick={() => { setTempToken(null); setTwoFactorCode(""); }}
                  className="btn btn-ghost login-btn-back"
                >
                  Terug naar inloggen
                </button>
              </form>
            )}
          </div>

          {/* Footer */}
          <div className="login-footer">
            <YingaFooter />
          </div>
        </div>
      </div>
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

/** Decode user info from JWT payload as fallback when backend omits role field */
function decodeUserFromToken(token: string) {
  try {
    const payload = JSON.parse(atob(token.split(".")[1]));
    return {
      id: payload.sub || payload.user_id || "",
      email: payload.email || "",
      name: payload.name || payload.email || "",
      role: payload.role || "user",
      is_active: true,
      created_at: new Date().toISOString(),
    };
  } catch {
    return { id: "", email: "", name: "", role: "user" as const, is_active: true, created_at: "" };
  }
}
