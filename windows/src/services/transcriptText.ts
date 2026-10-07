/** Whisper emphasis is presentation markup, never executable transcript HTML. */
export function transcriptText(value: string): string {
  return value.replace(/<\/?b\s*>/gi, "");
}

export function formatDuration(seconds: number): string {
  const total = Number.isFinite(seconds) ? Math.max(0, Math.floor(seconds)) : 0;
  const minutes = Math.floor(total / 60);
  return minutes ? `${minutes}m ${total % 60}s` : `${total}s`;
}

export function processingError(error: unknown): string {
  const message = error instanceof Error ? error.message : String(error);
  if (/401|403/.test(message)) return "De AI-sleutel is ongeldig of heeft geen toegang. Controleer de sleutel in Instellingen → Verwerking. Je transcriptie blijft bewaard.";
  if (/429/.test(message)) return "De AI-provider is tijdelijk overbelast of je limiet is bereikt. Probeer later opnieuw. Je transcriptie blijft bewaard.";
  if (/error sending request|failed to fetch|connection refused|connect error|502|503|504/i.test(message)) return "De AI-provider is niet bereikbaar. Start je lokale AI of controleer de verbinding in Instellingen → Verwerking. Je transcriptie blijft bewaard; probeer daarna opnieuw.";
  return message;
}
