import DOMPurify from "dompurify";

export const MAX_FILE_BYTES = 12 * 1024 * 1024;
export const MAX_IMAGE_BYTES = 2 * 1024 * 1024;
const fail = () => {
  throw Error(
    "Ongeldige huisstijl. Gebruik een .tvhuisstijl-bestand (versie 1), PNG/JPEG-afbeeldingen tot 2 MB en maximaal 12 MB totaal.",
  );
};
export function validateImage(value) {
  if (value === "") return;
  if (
    typeof value !== "string" ||
    value.length > (MAX_IMAGE_BYTES * 4) / 3 + 100
  )
    fail();
  const match = /^data:image\/(png|jpeg);base64,([A-Za-z0-9+/]+={0,2})$/.exec(
    value,
  );
  if (!match) fail();
  let bytes;
  try {
    bytes = Uint8Array.from(atob(match[2]), (c) => c.charCodeAt(0));
  } catch {
    fail();
  }
  if (bytes.length > MAX_IMAGE_BYTES || bytes.length < 16) fail();
  if (
    match[1] === "png"
      ? ![137, 80, 78, 71, 13, 10, 26, 10].every((b, i) => bytes[i] === b)
      : !(bytes[0] === 255 && bytes[1] === 216 && bytes[2] === 255)
  )
    fail();
}
export async function validateAssets(b) {
  for (const key of ["logo", "coverBanner", "headerBanner", "footerBanner"]) {
    if (!b[key]) continue;
    validateImage(b[key]);
    const image = new Image();
    image.src = b[key];
    try {
      await image.decode();
    } catch {
      fail();
    }
    if (
      !image.naturalWidth ||
      !image.naturalHeight ||
      image.naturalWidth > 10000 ||
      image.naturalHeight > 10000 ||
      image.naturalWidth * image.naturalHeight > 25000000
    )
      fail();
  }
}
export function validateBranding(b) {
  if (
    !b ||
    b.schemaVersion !== 1 ||
    !Number.isInteger(b.revision) ||
    b.revision < 1 ||
    !["compact", "cover"].includes(b.layout)
  )
    fail();
  for (const key of [
    "id",
    "name",
    "company",
    "contact",
    "header",
    "footer",
    "coverHeader",
    "coverFooter",
  ]) {
    if (
      typeof b[key] !== "string" ||
      b[key].length > 1200 ||
      /[\u0000-\u0008\u000b\u000c\u000e-\u001f]/.test(b[key])
    )
      fail();
  }
  if (
    !b.id.trim() ||
    !b.name.trim() ||
    b.id.length > 100 ||
    b.name.length > 120
  )
    fail();
  for (const key of ["textColor", "headingColor", "accentColor"])
    if (!/^#[0-9a-f]{6}$/i.test(b[key])) fail();
  for (const key of ["bodyFont", "headingFont"])
    if (!["Carlito", "Caladea"].includes(b[key])) fail();
  for (const [key, min, max] of [
    ["fontSize", 9, 20],
    ["lineHeight", 1, 2.5],
    ["marginTop", 15, 40],
    ["marginBottom", 15, 40],
    ["marginLeft", 10, 40],
    ["marginRight", 10, 40],
  ]) {
    if (!Number.isFinite(b[key]) || b[key] < min || b[key] > max) fail();
  }
  for (const key of ["pageNumbers", "runningHeader", "runningFooter"])
    if (typeof b[key] !== "boolean") fail();
  for (const key of ["logo", "coverBanner", "headerBanner", "footerBanner"])
    validateImage(b[key]);
  if (JSON.stringify(b).length > MAX_FILE_BYTES) fail();
  // Keep only the known schema, so imported code, URLs or future fields never become active.
  return Object.fromEntries(
    Object.keys(blankBranding()).map((key) => [key, b[key]]),
  );
}
export function blankBranding() {
  return {
    schemaVersion: 1,
    id: "thoughtvault",
    revision: 1,
    name: "Nieuwe huisstijl",
    company: "",
    contact: "",
    layout: "compact",
    textColor: "#262626",
    headingColor: "#333333",
    accentColor: "#7830D8",
    bodyFont: "Carlito",
    headingFont: "Carlito",
    fontSize: 11,
    lineHeight: 1.5,
    marginTop: 25,
    marginBottom: 25,
    marginLeft: 25,
    marginRight: 25,
    header: "",
    footer: "",
    coverHeader: "",
    coverFooter: "",
    pageNumbers: true,
    runningHeader: true,
    runningFooter: true,
    logo: "",
    coverBanner: "",
    headerBanner: "",
    footerBanner: "",
  };
}
export function standardBranding() {
  return { ...blankBranding(), name: "Standaard ThoughtVault" };
}
export function parseBranding(text) {
  if (typeof text !== "string" || text.length > MAX_FILE_BYTES) fail();
  return validateBranding(JSON.parse(text));
}
export function validateLibrary(value) {
  const defaultId = value?.defaultId ?? null;
  if (
    !value ||
    value.schemaVersion !== 1 ||
    !Array.isArray(value.styles) ||
    value.styles.length > 40 ||
    !(defaultId === null || typeof defaultId === "string")
  )
    fail();
  const styles = value.styles.map(validateBranding);
  if (
    new Set(styles.map((b) => b.id)).size !== styles.length ||
    (defaultId !== null && !styles.some((b) => b.id === defaultId))
  )
    fail();
  return { schemaVersion: 1, defaultId, styles };
}

export function sanitizeContent(html) {
  const doc = new DOMParser().parseFromString(
    DOMPurify.sanitize(html, {
      ALLOWED_TAGS: [
        "h1",
        "h2",
        "h3",
        "h4",
        "p",
        "div",
        "section",
        "span",
        "br",
        "strong",
        "b",
        "em",
        "i",
        "u",
        "s",
        "ul",
        "ol",
        "li",
        "table",
        "thead",
        "tbody",
        "tfoot",
        "tr",
        "th",
        "td",
        "blockquote",
        "a",
        "hr",
        "sup",
        "sub",
      ],
      ALLOWED_ATTR: ["href", "colspan", "rowspan", "start", "value"],
      ALLOW_DATA_ATTR: false,
    }),
    "text/html",
  );
  doc
    .querySelectorAll("div,section")
    .forEach((node) => node.replaceWith(...node.childNodes));
  doc.querySelectorAll("a").forEach((a) => {
    if (!/^https?:\/\//i.test(a.getAttribute("href") || ""))
      a.removeAttribute("href");
  });
  return doc.body.innerHTML;
}
export const escapeHTML = (text) =>
  String(text).replace(
    /[&<>"']/g,
    (c) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[
        c
      ],
  );
export const sample = {
  title: "Projectoverleg",
  html: "<h2>Kern</h2><p>Het team bespreekt de planning, voortgang en de volgende stappen.</p><h2>Besluiten</h2><ul><li>De eerste versie wordt volgende week beoordeeld.</li></ul><h2>Acties</h2><table><thead><tr><th>Actie</th><th>Eigenaar</th><th>Wanneer</th></tr></thead><tbody><tr><td>Planning afstemmen</td><td>Sam</td><td>Vrijdag</td></tr></tbody></table><h2>Openstaande punten</h2><p>De definitieve opleverdatum volgt na de beoordeling.</p>",
};
