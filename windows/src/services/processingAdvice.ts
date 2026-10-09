import type { SystemSpecs } from "./tauriCommands";

// CPU guidance, not a compatibility test or measured transcription speed.
export function transcriptionAdvice(specs: SystemSpecs | null) {
  const known = Boolean(specs && Number.isFinite(specs.memory_gb) && specs.memory_gb > 0
    && Number.isFinite(specs.threads) && specs.threads > 0);
  const medium = Boolean(known && specs && specs.memory_gb >= 16 && specs.threads >= 8);
  const limited = Boolean(known && specs && (specs.memory_gb < 8 || specs.threads < 4));
  return {
    models: !known ? [] : medium ? ["small", "medium"] : ["small"],
    model: !known ? null : medium ? "medium" : "small",
    name: !known ? "Systeemadvies niet beschikbaar" : medium ? "Whisper Medium" : "Whisper Small",
    reason: !known ? "Systeemgegevens ontbreken. Je kunt zelf een model kiezen; we kunnen nu geen betrouwbaar advies geven."
      : limited ? "Deze pc heeft weinig geheugen of processorthreads voor transcriptie naast een videocall. Small is de lichtste keuze in deze app. Verwerking kan lang duren; cloudtranscriptie is een alternatief."
      : medium ? "Medium is een voorlopige aanbeveling op basis van totaal RAM en processorthreads. Small verwerkt doorgaans sneller."
      : "Small is onze voorlopige aanbeveling op basis van totaal RAM en processorthreads. Zwaardere modellen kunnen meer tijd en geheugen vragen.",
  };
}
