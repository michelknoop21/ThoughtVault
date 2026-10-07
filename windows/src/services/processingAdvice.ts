import type { SystemSpecs } from "./tauriCommands";

// Windows currently builds whisper.cpp for CPU inference. Give conservative
// advice based on the real available hardware; never promise GPU acceleration.
export function transcriptionAdvice(specs: SystemSpecs | null) {
  const medium = Boolean(specs && specs.memory_gb >= 16 && specs.threads >= 8);
  return {
    model: medium ? "medium" : "small",
    name: medium ? "Whisper Medium" : "Whisper Small",
    reason: !specs ? "Systeemgegevens nog niet beschikbaar. Small vraagt minder geheugen en is een veilige start."
      : medium ? "Deze pc heeft voldoende geheugen en processorkernen voor Medium: een balans tussen Nederlandse herkenningskwaliteit en CPU-belasting."
      : "Small past beter bij het geheugen en de processorkernen van deze pc. Medium en Large zijn handmatig beschikbaar, maar vragen meer tijd en geheugen.",
  };
}
