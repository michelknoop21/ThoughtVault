// Expected setup/empty-input notices remain visible without creating a support incident.
const expectedNotices = new Set([
  "Transcriptiemodel ontbreekt. Download het gekozen model bij Instellingen → Verwerking en verwerk daarna deze opname opnieuw. De opname wordt niet gewijzigd.",
  "Geen bruikbare spraak herkend. Controleer de opname en probeer opnieuw.",
  "Vul je Ollama Cloud API-sleutel in bij Instellingen.",
  "Vul je OpenAI API-sleutel in bij Instellingen.",
  "Vul je Anthropic API-sleutel in bij Instellingen.",
]);

export function isExpectedProcessingNotice(message: string | undefined): boolean {
  return message !== undefined && expectedNotices.has(message);
}
