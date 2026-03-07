import { useState, useEffect } from "react";
import {
  Person24Regular,
  Edit24Regular,
  Checkmark24Regular,
  Key24Regular,
  ShieldLock24Regular,
  ShieldCheckmark24Regular,
  Mail24Regular,
  SignOut24Regular,
} from "@fluentui/react-icons";
import { useAuthStore } from "../stores/authStore";
import { api } from "../services/api";
import { useToast } from "../components/ui/InfoBar";
import type { TwoFAStatus, TwoFASetupResponse, TwoFAVerifyResponse } from "../types";

export function AccountPage() {
  const { user, logout, updateUserName } = useAuthStore();
  const toast = useToast();

  // Name editing state
  const [isEditingName, setIsEditingName] = useState(false);
  const [editName, setEditName] = useState(user?.name || "");

  function handleSaveName() {
    const trimmed = editName.trim();
    if (trimmed) {
      updateUserName(trimmed);
      toast.show("Naam opgeslagen", "success");
    }
    setIsEditingName(false);
  }

  // Password change state
  const [currentPassword, setCurrentPassword] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [passwordLoading, setPasswordLoading] = useState(false);

  // 2FA state
  const [twoFAStatus, setTwoFAStatus] = useState<TwoFAStatus | null>(null);
  const [twoFALoading, setTwoFALoading] = useState(false);
  const [setupData, setSetupData] = useState<TwoFASetupResponse | null>(null);
  const [verifyCode, setVerifyCode] = useState("");
  const [backupCodes, setBackupCodes] = useState<string[] | null>(null);
  const [disablePassword, setDisablePassword] = useState("");
  const [showDisableForm, setShowDisableForm] = useState(false);

  // Load 2FA status on mount
  useEffect(() => {
    load2FAStatus();
  }, []);

  async function load2FAStatus() {
    try {
      const status = await api.get2FAStatus();
      setTwoFAStatus(status);
    } catch {
      // Silently fail — status will show as unknown
    }
  }

  // Password change handler
  async function handleChangePassword(e: React.FormEvent) {
    e.preventDefault();
    if (newPassword !== confirmPassword) {
      toast.show("Wachtwoorden komen niet overeen", "error");
      return;
    }
    if (newPassword.length < 8) {
      toast.show("Wachtwoord moet minimaal 8 tekens bevatten", "error");
      return;
    }
    setPasswordLoading(true);
    try {
      await api.changePassword(currentPassword, newPassword);
      toast.show("Wachtwoord succesvol gewijzigd", "success");
      setCurrentPassword("");
      setNewPassword("");
      setConfirmPassword("");
    } catch (err) {
      toast.show(err instanceof Error ? err.message : "Wachtwoord wijzigen mislukt", "error");
    } finally {
      setPasswordLoading(false);
    }
  }

  // 2FA setup flow
  async function handleSetup2FA() {
    setTwoFALoading(true);
    try {
      const data = await api.setup2FA();
      setSetupData(data);
      setVerifyCode("");
      setBackupCodes(null);
    } catch (err) {
      toast.show(err instanceof Error ? err.message : "2FA instellen mislukt", "error");
    } finally {
      setTwoFALoading(false);
    }
  }

  async function handleVerify2FASetup(e: React.FormEvent) {
    e.preventDefault();
    if (!/^\d{6}$/.test(verifyCode)) {
      toast.show("Code moet exact 6 cijfers zijn", "error");
      return;
    }
    setTwoFALoading(true);
    try {
      const result: TwoFAVerifyResponse = await api.verify2FASetup(verifyCode);
      setBackupCodes(result.backup_codes);
      setSetupData(null);
      setTwoFAStatus({ enabled: true, backup_codes_remaining: result.backup_codes.length });
      toast.show("Twee-factor authenticatie geactiveerd", "success");
    } catch (err) {
      toast.show(err instanceof Error ? err.message : "Verificatiecode ongeldig", "error");
    } finally {
      setTwoFALoading(false);
    }
  }

  async function handleDisable2FA(e: React.FormEvent) {
    e.preventDefault();
    if (!disablePassword) return;
    setTwoFALoading(true);
    try {
      await api.disable2FA(disablePassword);
      setTwoFAStatus({ enabled: false });
      setShowDisableForm(false);
      setDisablePassword("");
      setBackupCodes(null);
      toast.show("Twee-factor authenticatie uitgeschakeld", "success");
    } catch (err) {
      toast.show(err instanceof Error ? err.message : "2FA uitschakelen mislukt", "error");
    } finally {
      setTwoFALoading(false);
    }
  }

  async function handleRegenerateBackupCodes() {
    setTwoFALoading(true);
    try {
      const result: TwoFAVerifyResponse = await api.regenerateBackupCodes();
      setBackupCodes(result.backup_codes);
      setTwoFAStatus((prev) => prev ? { ...prev, backup_codes_remaining: result.backup_codes.length } : prev);
      toast.show("Backup codes opnieuw gegenereerd", "success");
    } catch (err) {
      toast.show(err instanceof Error ? err.message : "Backup codes genereren mislukt", "error");
    } finally {
      setTwoFALoading(false);
    }
  }

  async function handleLogout() {
    await api.logout();
    logout();
  }

  // Format "lid sinds" date
  const memberSince = user?.created_at
    ? new Date(user.created_at).toLocaleDateString("nl-NL", { year: "numeric", month: "long", day: "numeric" })
    : undefined;

  return (
    <div className="page-scroll">
      {/* Page header */}
      <div className="page-header">
        <h1 className="page-title-sm">Account</h1>
      </div>

      {/* Scrollable content */}
      <div className="page-content">
        <div className="page-content-narrow">

          {/* Profiel info */}
          <div className="settings-group">
            <p className="settings-group-label">Profiel</p>
            <div className="settings-row">
              <div className="flex-row gap-10 flex-1">
                <div className="avatar avatar-accent">
                  {(user?.name || user?.email || "?").charAt(0).toUpperCase()}
                </div>
                <div className="flex-1">
                  {isEditingName ? (
                    <div className="flex-row gap-8" style={{ alignItems: "center", flexWrap: "wrap" }}>
                      <input
                        type="text"
                        value={editName}
                        onChange={(e) => setEditName(e.target.value)}
                        onKeyDown={(e) => {
                          if (e.key === "Enter") handleSaveName();
                          if (e.key === "Escape") setIsEditingName(false);
                        }}
                        className="input"
                        style={{ flex: 1, minWidth: 120, padding: "5px 8px", fontSize: 13 }}
                        autoFocus
                        placeholder="Je volledige naam"
                      />
                      <button
                        onClick={handleSaveName}
                        className="btn btn-accent btn-sm"
                      >
                        <Checkmark24Regular style={{ fontSize: 14 }} />
                        Opslaan
                      </button>
                    </div>
                  ) : (
                    <div className="flex-row gap-8" style={{ alignItems: "center" }}>
                      <p className="settings-label">
                        {user?.name || <span style={{ color: "var(--text-tertiary)", fontStyle: "italic" }}>Naam niet ingesteld</span>}
                      </p>
                      <button
                        onClick={() => { setEditName(user?.name || ""); setIsEditingName(true); }}
                        className="icon-btn icon-btn-sm"
                        title="Naam bewerken"
                      >
                        <Edit24Regular style={{ fontSize: 14 }} />
                      </button>
                    </div>
                  )}
                  <p className="settings-desc">{user?.email}</p>
                  {memberSince && (
                    <p className="settings-desc" style={{ marginTop: 2 }}>
                      Lid sinds {memberSince}
                    </p>
                  )}
                </div>
                <span className="status-badge-accent">
                  {user?.role === "admin" ? "Admin" : "Gebruiker"}
                </span>
              </div>
            </div>
          </div>

          {/* Wachtwoord wijzigen */}
          <div className="settings-group">
            <p className="settings-group-label">Wachtwoord wijzigen</p>
            <div className="settings-row">
              <div className="flex-row gap-10 flex-1">
                <Key24Regular className="settings-icon" />
                <div className="flex-1">
                  <p className="settings-label">Wachtwoord</p>
                  <p className="settings-desc">Wijzig je huidige wachtwoord</p>
                </div>
              </div>
            </div>
            <form onSubmit={handleChangePassword} style={{ padding: "0 14px 12px" }}>
              <div className="flex-col gap-10">
                <div className="form-field">
                  <label className="form-label-sm">Huidig wachtwoord</label>
                  <input
                    type="password"
                    value={currentPassword}
                    onChange={(e) => setCurrentPassword(e.target.value)}
                    className="input"
                    required
                    autoComplete="current-password"
                  />
                </div>
                <div className="form-field">
                  <label className="form-label-sm">Nieuw wachtwoord</label>
                  <input
                    type="password"
                    value={newPassword}
                    onChange={(e) => setNewPassword(e.target.value)}
                    className="input"
                    required
                    minLength={8}
                    autoComplete="new-password"
                  />
                </div>
                <div className="form-field">
                  <label className="form-label-sm">Bevestig nieuw wachtwoord</label>
                  <input
                    type="password"
                    value={confirmPassword}
                    onChange={(e) => setConfirmPassword(e.target.value)}
                    className="input"
                    required
                    minLength={8}
                    autoComplete="new-password"
                  />
                </div>
                <div>
                  <button
                    type="submit"
                    className="btn btn-accent"
                    disabled={passwordLoading || !currentPassword || !newPassword || !confirmPassword}
                    style={{ padding: "7px 14px", fontSize: 12 }}
                  >
                    {passwordLoading ? "Wijzigen..." : "Wachtwoord wijzigen"}
                  </button>
                </div>
              </div>
            </form>
          </div>

          {/* Twee-factor authenticatie */}
          <div className="settings-group">
            <p className="settings-group-label">Twee-factor authenticatie (2FA)</p>
            <div className="settings-row">
              <div className="flex-row gap-10 flex-1">
                <ShieldLock24Regular className="settings-icon" />
                <div className="flex-1">
                  <p className="settings-label">2FA</p>
                  <p className="settings-desc">
                    {twoFAStatus === null
                      ? "Status laden..."
                      : twoFAStatus.enabled
                      ? `Actief — ${twoFAStatus.backup_codes_remaining ?? "?"} backup codes resterend`
                      : "Niet geactiveerd"}
                  </p>
                </div>
                {twoFAStatus?.enabled && (
                  <span className="status-badge-accent">
                    <ShieldCheckmark24Regular style={{ fontSize: 14, marginRight: 4 }} />
                    Actief
                  </span>
                )}
              </div>
            </div>

            <div style={{ padding: "0 14px 12px" }}>
              {/* 2FA not enabled — show activate button or setup flow */}
              {twoFAStatus && !twoFAStatus.enabled && !setupData && (
                <button
                  onClick={handleSetup2FA}
                  className="btn btn-accent"
                  disabled={twoFALoading}
                  style={{ padding: "7px 14px", fontSize: 12 }}
                >
                  {twoFALoading ? "Laden..." : "2FA activeren"}
                </button>
              )}

              {/* QR code setup step */}
              {setupData && !backupCodes && (
                <div className="flex-col gap-10">
                  <p className="settings-desc">
                    Scan de QR-code met je authenticator app (bijv. Google Authenticator, Authy):
                  </p>
                  <div style={{ textAlign: "center", padding: "8px 0" }}>
                    <img
                      src={setupData.qr_code}
                      alt="2FA QR Code"
                      style={{ width: 180, height: 180, borderRadius: 8, background: "#fff", padding: 8 }}
                    />
                  </div>
                  <div className="form-field">
                    <label className="form-label-sm">Of voer deze code handmatig in:</label>
                    <code style={{
                      display: "block",
                      padding: "8px 10px",
                      background: "var(--bg-card-secondary)",
                      borderRadius: 6,
                      fontSize: 13,
                      letterSpacing: "1px",
                      wordBreak: "break-all",
                      userSelect: "all",
                    }}>
                      {setupData.secret}
                    </code>
                  </div>
                  <form onSubmit={handleVerify2FASetup} className="flex-col gap-10">
                    <div className="form-field">
                      <label className="form-label-sm">Verificatiecode (6 cijfers)</label>
                      <input
                        type="text"
                        value={verifyCode}
                        onChange={(e) => setVerifyCode(e.target.value.replace(/\D/g, "").slice(0, 6))}
                        className="input"
                        placeholder="000000"
                        maxLength={6}
                        pattern="\d{6}"
                        required
                        autoComplete="one-time-code"
                        style={{ maxWidth: 200, letterSpacing: "4px", textAlign: "center" }}
                      />
                    </div>
                    <div className="flex-row gap-8" style={{ flexWrap: "wrap" }}>
                      <button
                        type="submit"
                        className="btn btn-accent btn-sm"
                        disabled={twoFALoading || verifyCode.length !== 6}
                      >
                        {twoFALoading ? "Verifiëren..." : "Verifiëren en activeren"}
                      </button>
                      <button
                        type="button"
                        onClick={() => { setSetupData(null); setVerifyCode(""); }}
                        className="btn btn-secondary btn-sm"
                      >
                        Annuleren
                      </button>
                    </div>
                  </form>
                </div>
              )}

              {/* Backup codes display */}
              {backupCodes && (
                <div className="flex-col gap-10">
                  <p className="settings-desc" style={{ color: "var(--fill-system-caution)" }}>
                    Bewaar deze backup codes op een veilige plek. Ze kunnen elk eenmalig worden gebruikt om in te loggen als je geen toegang hebt tot je authenticator app.
                  </p>
                  <div style={{
                    display: "grid",
                    gridTemplateColumns: "1fr 1fr",
                    gap: 6,
                    padding: "10px 12px",
                    background: "var(--bg-card-secondary)",
                    borderRadius: 8,
                  }}>
                    {backupCodes.map((code) => (
                      <code key={code} style={{ fontSize: 13, letterSpacing: "1px", fontFamily: "monospace" }}>
                        {code}
                      </code>
                    ))}
                  </div>
                  <button
                    onClick={() => setBackupCodes(null)}
                    className="btn btn-secondary btn-sm"
                    style={{ alignSelf: "flex-start" }}
                  >
                    Begrepen, sluiten
                  </button>
                </div>
              )}

              {/* 2FA enabled — disable + regenerate buttons */}
              {twoFAStatus?.enabled && !backupCodes && !setupData && (
                <div className="flex-col gap-10">
                  {/* Disable form */}
                  {showDisableForm ? (
                    <form onSubmit={handleDisable2FA} className="flex-col gap-10">
                      <div className="form-field">
                        <label className="form-label-sm">Wachtwoord ter bevestiging</label>
                        <input
                          type="password"
                          value={disablePassword}
                          onChange={(e) => setDisablePassword(e.target.value)}
                          className="input"
                          required
                          autoComplete="current-password"
                          style={{ maxWidth: 300 }}
                        />
                      </div>
                      <div className="flex-row gap-8" style={{ flexWrap: "wrap" }}>
                        <button
                          type="submit"
                          className="btn btn-secondary btn-sm"
                          disabled={twoFALoading || !disablePassword}
                          style={{ color: "var(--text-error)", borderColor: "rgba(188,0,22,0.3)" }}
                        >
                          {twoFALoading ? "Uitschakelen..." : "Bevestigen"}
                        </button>
                        <button
                          type="button"
                          onClick={() => { setShowDisableForm(false); setDisablePassword(""); }}
                          className="btn btn-secondary btn-sm"
                        >
                          Annuleren
                        </button>
                      </div>
                    </form>
                  ) : (
                    <div className="flex-row gap-8" style={{ flexWrap: "wrap" }}>
                      <button
                        onClick={() => setShowDisableForm(true)}
                        className="btn btn-secondary btn-sm"
                        style={{ color: "var(--text-error)", borderColor: "rgba(188,0,22,0.3)" }}
                      >
                        2FA deactiveren
                      </button>
                      <button
                        onClick={handleRegenerateBackupCodes}
                        className="btn btn-secondary btn-sm"
                        disabled={twoFALoading}
                      >
                        {twoFALoading ? "Genereren..." : "Backup codes opnieuw genereren"}
                      </button>
                    </div>
                  )}
                </div>
              )}
            </div>
          </div>

          {/* Privacy & Gegevens (GDPR) */}
          <div className="settings-group">
            <p className="settings-group-label">Privacy & gegevens</p>
            <div className="settings-row">
              <div className="flex-row gap-10 flex-1">
                <Person24Regular className="settings-icon" />
                <div className="flex-1">
                  <p className="settings-label">Gegevens exporteren (AVG)</p>
                  <p className="settings-desc">Download al je opnames en transcripties</p>
                </div>
              </div>
            </div>
            <div style={{ padding: "0 14px 4px" }}>
              <button
                className="btn btn-secondary"
                style={{ padding: "7px 14px", fontSize: 12 }}
                onClick={() => toast.show("Data export is nog niet beschikbaar", "info")}
              >
                Gegevens exporteren
              </button>
            </div>
            <div className="settings-row">
              <div className="flex-row gap-10 flex-1">
                <Mail24Regular className="settings-icon" style={{ color: "var(--fill-system-critical)" }} />
                <div className="flex-1">
                  <p className="settings-label">Account verwijderen</p>
                  <p className="settings-desc">
                    Neem contact op met{" "}
                    <a
                      href="mailto:support@yinga.nl?subject=Account%20verwijderen%20TranscriptStudio"
                      style={{ color: "var(--text-accent)", textDecoration: "none" }}
                    >
                      support@yinga.nl
                    </a>
                    {" "}om je account te laten verwijderen. Verzoeken worden binnen 30 dagen verwerkt conform de AVG.
                  </p>
                </div>
              </div>
            </div>
          </div>

          {/* Uitloggen */}
          <div className="settings-group">
            <p className="settings-group-label">Sessie</p>
            <div className="settings-row">
              <div className="flex-row gap-10 flex-1">
                <SignOut24Regular className="settings-icon" style={{ color: "var(--fill-system-critical)" }} />
                <div className="flex-1">
                  <p className="settings-label">Uitloggen</p>
                  <p className="settings-desc">Beëindig je huidige sessie</p>
                </div>
              </div>
            </div>
            <div style={{ padding: "0 14px 12px" }}>
              <button
                onClick={handleLogout}
                className="btn btn-secondary"
                style={{ fontSize: 12, color: "var(--text-error)", borderColor: "rgba(188,0,22,0.3)" }}
              >
                Uitloggen
              </button>
            </div>
          </div>

        </div>
      </div>
    </div>
  );
}
