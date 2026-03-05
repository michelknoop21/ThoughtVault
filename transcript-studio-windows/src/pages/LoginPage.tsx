import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { api } from "../services/api";
import { useAuthStore } from "../stores/authStore";

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
      const response = await api.verify2FA(tempToken, twoFactorCode);
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
    <div
      style={{
        height: "100%",
        display: "flex",
        flexDirection: "column",
        background: "var(--bg-solid-tertiary)",
      }}
    >
      {/* Minimal drag region */}
      <div
        data-tauri-drag-region
        style={{ height: 40, flexShrink: 0 }}
      />

      {/* Brand bar */}
      <div className="brand-bar" />

      <div
        style={{
          flex: 1,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          padding: 32,
        }}
      >
        <div style={{ width: "100%", maxWidth: 360 }}>
          {/* Logo & title */}
          <div style={{ textAlign: "center", marginBottom: 32 }}>
            <div
              style={{
                width: 64,
                height: 64,
                background: "var(--fill-accent-default)",
                borderRadius: 16,
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                margin: "0 auto 16px",
                boxShadow: "var(--shadow-md)",
              }}
            >
              <span style={{ fontSize: 28, color: "#fff", fontWeight: 700 }}>TS</span>
            </div>
            <h1
              style={{
                fontSize: 24,
                fontWeight: 600,
                color: "var(--text-primary)",
                margin: 0,
              }}
            >
              Transcript Studio
            </h1>
            <p
              style={{
                fontSize: 14,
                color: "var(--text-tertiary)",
                marginTop: 4,
              }}
            >
              {tempToken ? "Voer uw authenticatiecode in" : "Log in om door te gaan"}
            </p>
          </div>

          {/* Error */}
          {error && (
            <div
              style={{
                marginBottom: 16,
                padding: "10px 14px",
                background: "rgba(188, 0, 22, 0.08)",
                border: "1px solid rgba(188, 0, 22, 0.25)",
                borderRadius: 8,
                fontSize: 13,
                color: "var(--text-error)",
              }}
            >
              {error}
            </div>
          )}

          {/* Form */}
          <div
            className="card-elevated"
            style={{ padding: 24, borderRadius: 12 }}
          >
            {!tempToken ? (
              <form onSubmit={handleLogin} style={{ display: "flex", flexDirection: "column", gap: 16 }}>
                <FormField label="E-mailadres">
                  <input
                    type="email"
                    value={email}
                    onChange={(e) => setEmail(e.target.value)}
                    required
                    autoFocus
                    placeholder="naam@bedrijf.nl"
                    style={inputStyle}
                  />
                </FormField>

                <FormField label="Wachtwoord">
                  <input
                    type="password"
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                    required
                    placeholder="••••••••"
                    style={inputStyle}
                  />
                </FormField>

                <button
                  type="submit"
                  disabled={isLoading}
                  className="btn btn-accent"
                  style={{ width: "100%", padding: "9px 16px", fontSize: 14, fontWeight: 600 }}
                >
                  {isLoading ? "Inloggen..." : "Inloggen"}
                </button>
              </form>
            ) : (
              <form onSubmit={handle2FA} style={{ display: "flex", flexDirection: "column", gap: 16 }}>
                <FormField label="Authenticatiecode">
                  <input
                    type="text"
                    value={twoFactorCode}
                    onChange={(e) => setTwoFactorCode(e.target.value.replace(/\D/g, ""))}
                    required
                    autoFocus
                    maxLength={6}
                    placeholder="000000"
                    style={{
                      ...inputStyle,
                      textAlign: "center",
                      fontSize: 24,
                      letterSpacing: "0.4em",
                    }}
                  />
                </FormField>

                <button
                  type="submit"
                  disabled={isLoading || twoFactorCode.length !== 6}
                  className="btn btn-accent"
                  style={{ width: "100%", padding: "9px 16px", fontSize: 14, fontWeight: 600 }}
                >
                  {isLoading ? "Verifiëren..." : "Verifiëren"}
                </button>

                <button
                  type="button"
                  onClick={() => { setTempToken(null); setTwoFactorCode(""); }}
                  className="btn btn-ghost"
                  style={{ width: "100%", fontSize: 13 }}
                >
                  Terug naar inloggen
                </button>
              </form>
            )}
          </div>

          {/* Footer */}
          <p
            style={{
              textAlign: "center",
              fontSize: 12,
              color: "var(--text-disabled)",
              marginTop: 24,
            }}
          >
            © 2026 Prezent Internet B.V.
          </p>
        </div>
      </div>
    </div>
  );
}

function FormField({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 4 }}>
      <label style={{ fontSize: 13, fontWeight: 500, color: "var(--text-secondary)" }}>
        {label}
      </label>
      {children}
    </div>
  );
}

const inputStyle: React.CSSProperties = {
  width: "100%",
  padding: "7px 10px",
  background: "var(--fill-control-default)",
  border: "1px solid var(--stroke-control-secondary)",
  borderBottom: "1px solid var(--stroke-control-default)",
  borderRadius: 6,
  color: "var(--text-primary)",
  fontSize: 14,
  outline: "none",
};

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
