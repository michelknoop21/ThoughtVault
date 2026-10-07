import { expect, it } from "vitest";
import { transcriptText, formatDuration, processingError } from "../transcriptText";
it("removes Whisper emphasis without interpreting arbitrary user HTML", () => {
  expect(transcriptText('<b>Actie</b> <script>alert(1)</script> 2 < 3')).toBe('Actie <script>alert(1)</script> 2 < 3');
});
it("formats finite whole seconds", () => {
  expect(formatDuration(77.044177875000003)).toBe("1m 17s");
  expect(formatDuration(NaN)).toBe("0s");
  expect(formatDuration(-1)).toBe("0s");
});
it("explains unreachable AI and retained transcripts", () => {
  expect(processingError(new Error('error sending request for url (http://localhost:11434/v1/chat/completions)'))).toContain('Je transcriptie blijft bewaard');
  expect(processingError('HTTP 502')).toContain('niet bereikbaar');
});
