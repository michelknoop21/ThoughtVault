export function hasUsableTranscription(text: string): boolean {
  const spoken = text.replace(/\b(ruis|stilte|onverstaanbaar|muziek|applaus|gelach)\b/gi, "");
  return (spoken.match(/[\p{L}\p{N}]/gu) ?? []).length >= 10
    && !/^(geen transcriptie|transcriptie ontbreekt|onvoldoende transcriptie)[.!\s]*$/i.test(text.trim());
}

export function hasUsableNotule(html: string): boolean {
  const document = new DOMParser().parseFromString(html, "text/html");
  document.querySelectorAll("style, script, template").forEach((node) => node.remove());
  const text = (document.body.textContent ?? "").trim();
  if ((text.match(/[\p{L}\p{N}]/gu) ?? []).length < 20) return false;
  if (/\[[^\]]+\]/.test(text)) return false;
  if (/geen transcriptie|transcriptie ontbreekt|onvoldoende transcriptie/i.test(text)) return false;
  return true;
}
