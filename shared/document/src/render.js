import {
  standardBranding,
  validateBranding,
  sanitizeContent,
  escapeHTML,
} from "./branding.js";
import bundled from "./bundled.json";
export { bundled };
export function fontCSS() {
  return Object.entries(bundled.fonts)
    .map(([key, url]) => {
      const [name, face] = key.split("-");
      return `@font-face{font-family:${name};src:url(${url});font-weight:${face.includes("Bold") ? 700 : 400};font-style:${face.includes("Italic") ? "italic" : "normal"}} `;
    })
    .join("");
}
export function renderDocument({
  html,
  title = "",
  subtitle = "",
  branding = null,
  editable = false,
}) {
  const b = branding
    ? validateBranding(
        typeof branding === "string" ? JSON.parse(branding) : branding,
      )
    : standardBranding();
  const image = (src, cls) =>
    src ? `<img class="${cls}" alt="" src="${src}">` : "";
  const content = sanitizeContent(html);
  const text = (value) => escapeHTML(value).replace(/\n/g, "<br>");
  const head = b.runningHeader
    ? `${image(b.logo, "logo")}<span>${text(b.header)}</span>${image(b.headerBanner, "header-banner")}`
    : "";
  const foot = b.runningFooter
    ? `${image(b.footerBanner, "footer-banner")}<span>${text(b.footer)}</span>`
    : "";
  const cover =
    b.layout === "cover"
      ? `<section class="tv-page tv-cover">${image(b.logo, "cover-logo")}<p>${text(b.coverHeader)}</p><h1>${text(title)}</h1>${subtitle ? `<p>${text(subtitle)}</p>` : ""}${image(b.coverBanner, "cover-banner")}<p>${text(b.company)}</p><p>${text(b.contact)}</p><div class="cover-foot">${text(b.coverFooter)}${image(b.footerBanner, "footer-banner")}</div></section>`
      : "";
  return `<!doctype html><html lang="nl"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; font-src data:; style-src 'unsafe-inline'"><title>${escapeHTML(title)}</title><!-- Bundled font licenses: ${Object.values(bundled.licenses).join("\n").replace(/--/g, "- -")} --><style>${fontCSS()}
*{box-sizing:border-box}html{color-scheme:light}body{margin:0;background:#e8e8ec;color:${b.textColor};font:${b.fontSize}pt ${b.bodyFont};line-height:${b.lineHeight}}.tv-page{position:relative;width:210mm;height:297mm;margin:12px auto;background:white;overflow:hidden;break-after:page;padding:${b.marginTop}mm ${b.marginRight}mm ${b.marginBottom}mm ${b.marginLeft}mm}.tv-page:last-child{break-after:auto}.tv-body{height:100%;overflow:hidden}.tv-header{position:absolute;top:4mm;left:${b.marginLeft}mm;right:${b.marginRight}mm;height:${b.marginTop - 7}mm;display:flex;gap:8mm;align-items:center;font:9pt ${b.headingFont};overflow:hidden}.logo{max-height:12mm;max-width:32mm;object-fit:contain}.header-banner{position:absolute;bottom:0;width:100%;height:1mm}.tv-footer{position:absolute;bottom:3mm;left:${b.marginLeft}mm;right:${b.marginRight}mm;height:${b.marginBottom - 6}mm;font:8pt ${b.headingFont};overflow:hidden;display:flex;align-items:end;justify-content:space-between}.footer-banner{position:absolute;inset:0;width:100%;height:100%;object-fit:cover;opacity:1}.tv-footer span,.tv-footer b{position:relative;background:#ffffffdd;padding:1mm 2mm}.tv-cover{padding-top:20mm}.cover-logo{max-width:65mm;max-height:30mm;object-fit:contain}.cover-banner{width:calc(100% + ${b.marginLeft + b.marginRight}mm);max-height:75mm;object-fit:contain;margin:12mm -${b.marginLeft}mm}.cover-foot{position:absolute;bottom:0;left:0;right:0;min-height:29mm;padding:8mm ${b.marginLeft}mm}.cover-foot .footer-banner{z-index:0}.cover-foot{isolation:isolate}.cover-foot .footer-banner{z-index:-1}h1,h2,h3,h4{font-family:${b.headingFont};color:${b.headingColor};line-height:1.2;break-after:avoid}h1{font-size:24pt;margin:0 0 9mm}h2{font-size:16pt;margin:7mm 0 3mm}h3{font-size:13pt;margin:5mm 0 2mm}p{margin:0 0 3mm}table{border-collapse:collapse;width:100%;margin:4mm 0;table-layout:fixed}th,td{border:1px solid #bbb;padding:2mm;vertical-align:top;overflow-wrap:anywhere}th{color:${b.headingColor};font-family:${b.headingFont};background:#f4f5f7}tr{break-inside:avoid}thead{display:table-header-group}li{margin:1mm 0}blockquote{border-left:3px solid ${b.accentColor};margin:4mm 0;padding-left:4mm}a{color:${b.accentColor}}.tv-content{overflow-wrap:anywhere}.tv-content:focus{outline:2px solid ${b.accentColor}}
.tv-editing .tv-page:not(.tv-cover){height:auto;min-height:297mm;overflow:visible}.tv-editing .tv-body{height:auto;overflow:visible}.tv-editing .tv-footer{position:relative;bottom:auto;left:0;right:0;margin-top:10mm;min-height:15mm}
@media print{@page{size:A4;margin:0}body{background:white}.tv-page{margin:0;box-shadow:none;zoom:1!important}}
@media screen and (max-width:820px){body{overflow-x:auto}.tv-page{margin:0 auto}}
</style></head><body class="${editable ? "tv-editing" : ""}">${cover}<section class="tv-page"><header class="tv-header">${head}</header><div class="tv-body"><div class="tv-content" ${editable ? 'contenteditable="true" role="textbox" aria-label="Notule-inhoud bewerken" aria-multiline="true"' : ""}>${title && !/<h1\b/i.test(content) ? `<h1>${text(title)}</h1>` : ""}${subtitle ? `<p>${text(subtitle)}</p>` : ""}${content}</div></div><footer class="tv-footer">${foot}${b.pageNumbers ? '<b class="tv-page-number"></b>' : ""}</footer></section></body></html>`;
}
export async function ready(doc = document) {
  if (doc.fonts) {
    await Promise.all(
      [
        "400 11pt Carlito",
        "700 11pt Carlito",
        "italic 11pt Carlito",
        "700 italic 11pt Carlito",
        "400 11pt Caladea",
        "700 11pt Caladea",
        "italic 11pt Caladea",
        "700 italic 11pt Caladea",
      ].map((font) => doc.fonts.load(font)),
    );
    await doc.fonts.ready;
    if (!doc.fonts.check("11pt Carlito") || !doc.fonts.check("11pt Caladea"))
      throw Error("Een meegeleverd lettertype kon niet worden geladen.");
  }
  await Promise.all(
    [...doc.images].map((image) =>
      image.complete
        ? Promise.resolve()
        : new Promise((resolve, reject) => {
            image.onload = resolve;
            image.onerror = () =>
              reject(Error("Een documentafbeelding kon niet worden geladen."));
          }),
    ),
  );
  if ([...doc.images].some((image) => !image.naturalWidth))
    throw Error("Een documentafbeelding ontbreekt.");
}
// Paginate the same DOM for on-screen pages, HTML and platform PDF printers.
export async function paginate(doc = document) {
  await ready(doc);
  const first = doc.querySelector(".tv-page:not(.tv-cover)");
  if (
    !first ||
    first.dataset.paginated ||
    first.querySelector("[contenteditable]")
  )
    return;
  first.dataset.paginated = "true";
  const template = first.cloneNode(true);
  const content = first.querySelector(".tv-content");
  const pending = [...content.childNodes]
    .filter((node) => node.nodeType !== 3 || node.textContent.trim())
    .map((node) => {
      if (node.nodeType !== 3) return node;
      const p = doc.createElement("p");
      p.textContent = node.textContent;
      return p;
    });
  content.replaceChildren();
  let page = first,
    target = content;
  const fits = () =>
    page.querySelector(".tv-body").scrollHeight <=
    page.querySelector(".tv-body").clientHeight + 1;
  const next = (keepHeadings = true) => {
    const headings = [];
    while (
      keepHeadings &&
      /^H[1-4]$/.test(target.lastElementChild?.tagName ?? "")
    )
      headings.unshift(target.removeChild(target.lastElementChild));
    if (!target.childNodes.length) {
      target.append(...headings);
      return;
    }
    const copy = template.cloneNode(true);
    copy.querySelector(".tv-content").replaceChildren();
    page.after(copy);
    page = copy;
    target = copy.querySelector(".tv-content");
    target.append(...headings);
  };
  for (let node of pending) {
    target.append(node);
    if (fits()) continue;
    node.remove();
    if (node.nodeType === 1 && ["TABLE", "UL", "OL"].includes(node.tagName)) {
      const parts =
        node.tagName === "TABLE"
          ? [...node.rows].filter(
              (row) => row.parentElement.tagName !== "THEAD",
            )
          : [...node.children];
      let fragment = node.cloneNode(false);
      if (node.tagName === "TABLE" && node.querySelector("thead"))
        fragment.append(node.querySelector("thead").cloneNode(true));
      let holder =
        node.tagName === "TABLE"
          ? fragment.appendChild(doc.createElement("tbody"))
          : fragment;
      target.append(fragment);
      for (const part of parts) {
        holder.append(part);
        if (!fits()) {
          part.remove();
          if (holder.children.length === 0) fragment.remove();
          next();
          fragment = node.cloneNode(false);
          if (node.tagName === "TABLE" && node.querySelector("thead"))
            fragment.append(node.querySelector("thead").cloneNode(true));
          holder =
            node.tagName === "TABLE"
              ? fragment.appendChild(doc.createElement("tbody"))
              : fragment;
          target.append(fragment);
          holder.append(part);
          // shortcut: one row or list item must fit A4; add cell/item splitting for oversized source blocks.
          if (!fits())
            throw Error(
              "Een tabelrij of lijstpunt past niet op A4. Verkort deze inhoud of kies kleinere letters.",
            );
        }
      }
      continue;
    }
    if (target.childNodes.length) next();
    target.append(node);
    if (!fits()) {
      // Split long rich paragraphs with DOM Ranges, preserving emphasis and links.
      while (!fits()) {
        const walker = doc.createTreeWalker(node, 4);
        const texts = [];
        let t;
        while ((t = walker.nextNode())) texts.push(t);
        if (node.nodeType === 3) texts.push(node);
        const total = texts.reduce((n, t) => n + t.length, 0);
        if (total < 2) throw Error("Dit inhoudsblok past niet op A4.");
        let lo = 1,
          hi = total - 1,
          best = 0;
        const cut = (offset) => {
          let n = offset;
          for (const text of texts) {
            if (n <= text.length) return [text, n];
            n -= text.length;
          }
          return [texts.at(-1), texts.at(-1).length];
        };
        const original = node.cloneNode(true);
        while (lo <= hi) {
          const mid = (lo + hi) >> 1;
          const [text, pos] = cut(mid);
          const range = doc.createRange();
          range.setStart(text, pos);
          range.setEndAfter(node.lastChild || node);
          const rest = range.extractContents();
          if (fits()) {
            best = mid;
            lo = mid + 1;
          } else hi = mid - 1;
          range.insertNode(rest);
          node.normalize();
          texts.length = 0;
          const w = doc.createTreeWalker(node, 4);
          while ((t = w.nextNode())) texts.push(t);
          if (node.nodeType === 3) texts.push(node);
        }
        node.replaceWith(original);
        node = original;
        if (!best) throw Error("Dit inhoudsblok past niet op A4.");
        texts.length = 0;
        const w = doc.createTreeWalker(node, 4);
        while ((t = w.nextNode())) texts.push(t);
        const [text, pos] = cut(best);
        const range = doc.createRange();
        range.setStart(text, pos);
        range.setEnd(node, node.childNodes.length);
        const rest = range.extractContents();
        const remainder = node.cloneNode(false);
        remainder.append(rest);
        next(false);
        target.append(remainder);
        node = remainder;
      }
    }
  }
  const pages = [...doc.querySelectorAll(".tv-page")];
  pages.forEach((p, i) => {
    const n = p.querySelector(".tv-page-number");
    if (n) n.textContent = `${i + 1} / ${pages.length}`;
  });
}
export function fitDocument(doc = document) {
  const page = doc.querySelector(".tv-page");
  if (!page) return;
  const scale = Math.min(1, doc.documentElement.clientWidth / page.offsetWidth);
  doc.querySelectorAll(".tv-page").forEach((page) => {
    page.style.zoom = String(scale);
  });
}
export async function standalone(options) {
  const frame = document.createElement("iframe");
  frame.style.cssText =
    "position:fixed;left:-10000px;width:900px;height:1200px";
  const loaded = new Promise((resolve) => (frame.onload = resolve));
  frame.srcdoc = renderDocument(options);
  document.body.append(frame);
  try {
    await loaded;
    await paginate(frame.contentDocument);
    return "<!doctype html>" + frame.contentDocument.documentElement.outerHTML;
  } finally {
    frame.remove();
  }
}
