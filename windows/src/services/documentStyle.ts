import DOMPurify from "dompurify";

export interface DocumentStyle {
  font: "Arial" | "Georgia" | "Verdana" | "Times New Roman";
  size: number;
  text_color: string;
  accent_color: string;
  line_height: number;
  margin_mm: number;
  paper: "A4" | "Letter";
  orientation: "portrait" | "landscape";
}

const defaults: DocumentStyle = {
  font: "Arial", size: 11, text_color: "#222222", accent_color: "#3454d1",
  line_height: 1.5, margin_mm: 20, paper: "A4", orientation: "portrait",
};

export function validateDocumentStyle(value: Partial<DocumentStyle> = {}): DocumentStyle {
  const style = { ...defaults, ...value };
  if (Object.keys(value).some((key) => !(key in defaults)) ||
    !["Arial", "Georgia", "Verdana", "Times New Roman"].includes(style.font) ||
    !["A4", "Letter"].includes(style.paper) || !["portrait", "landscape"].includes(style.orientation) ||
    !/^#[0-9a-f]{6}$/i.test(style.text_color) || !/^#[0-9a-f]{6}$/i.test(style.accent_color) ||
    !Number.isFinite(style.size) || style.size < 8 || style.size > 32 ||
    !Number.isFinite(style.line_height) || style.line_height < 1 || style.line_height > 2.5 ||
    !Number.isFinite(style.margin_mm) || style.margin_mm < 5 || style.margin_mm > 40) {
    throw Error("Ongeldige vormgeving.");
  }
  return style;
}

export function documentCSS(value: Partial<DocumentStyle>, selector = "body"): string {
  const s = validateDocumentStyle(value);
  return `@page{size:${s.paper} ${s.orientation};margin:${s.margin_mm}mm}` +
    `${selector}{font-family:"${s.font}";font-size:${s.size}pt;color:${s.text_color};line-height:${s.line_height};margin:0;background:#fff;${selector === "body" ? "" : `padding:${s.margin_mm}mm;`}}` +
    `${selector} h1,${selector} h2,${selector} h3{font-family:inherit;color:${s.accent_color}!important;line-height:inherit;border:0;padding:0;margin:1em 0 .5em}` +
    `${selector} h1{font-size:1.8em}${selector} h2{font-size:1.4em}${selector} h3{font-size:1.15em}` +
    `${selector} p,${selector} li,${selector} th,${selector} td{font-family:inherit;font-size:inherit;line-height:inherit;color:inherit!important}` +
    `${selector} p{margin:.5em 0}${selector} strong,${selector} em{color:inherit!important}` +
    `${selector} table{border-collapse:collapse;width:100%;font-size:inherit}${selector} th,${selector} td{border:1px solid #ddd;padding:6px;text-align:left;text-transform:none;letter-spacing:normal}` +
    `${selector} th{background:#f5f5f5!important}${selector} td{background:#fff!important}`;
}

export function minutesDocument(html: string, style: Partial<DocumentStyle> = {}): string {
  const clean = DOMPurify.sanitize(html, {
    FORBID_TAGS: ["style", "link", "img", "svg", "math", "iframe", "object", "embed", "video", "audio"],
    FORBID_ATTR: ["style", "src", "srcset"],
  });
  return `<!doctype html><html><head><meta charset="utf-8"><style>${documentCSS(style)}</style></head><body>${clean}</body></html>`;
}

export async function contentRevision(value: unknown): Promise<string> {
  const data = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(JSON.stringify(value)));
  return Array.from(new Uint8Array(data), (byte) => byte.toString(16).padStart(2, "0")).join("");
}
