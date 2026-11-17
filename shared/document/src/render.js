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
*{box-sizing:border-box}html{color-scheme:light;-webkit-text-size-adjust:100%;text-size-adjust:100%}body{margin:0;background:#e8e8ec;color:${b.textColor};font:${b.fontSize}pt ${b.bodyFont};line-height:${b.lineHeight};font-variant-ligatures:none}.tv-page{position:relative;width:210mm;height:297mm;margin:12px auto;background:white;overflow:hidden;break-after:page;padding:${b.marginTop}mm ${b.marginRight}mm ${b.marginBottom}mm ${b.marginLeft}mm}.tv-page:last-child{break-after:auto}.tv-page-frame{position:relative;overflow:hidden;margin:12px auto}.tv-page-frame>.tv-page{margin:0;transform-origin:top left}.tv-body{height:100%;overflow:hidden}.tv-header{position:absolute;top:4mm;left:${b.marginLeft}mm;right:${b.marginRight}mm;height:${b.marginTop - 7}mm;display:flex;gap:8mm;align-items:center;font:9pt ${b.headingFont};overflow:hidden}.logo{max-height:12mm;max-width:32mm;object-fit:contain}.header-banner{position:absolute;bottom:0;width:100%;height:1mm}.tv-footer{position:absolute;bottom:3mm;left:${b.marginLeft}mm;right:${b.marginRight}mm;height:${b.marginBottom - 6}mm;font:8pt ${b.headingFont};overflow:hidden;display:flex;align-items:end;justify-content:space-between}.footer-banner{position:absolute;inset:0;width:100%;height:100%;object-fit:cover;opacity:1}.tv-footer span,.tv-footer b{position:relative;background:#ffffffdd;padding:1mm 2mm}.tv-cover{padding-top:20mm}.cover-logo{max-width:65mm;max-height:30mm;object-fit:contain}.cover-banner{width:calc(100% + ${b.marginLeft + b.marginRight}mm);max-height:75mm;object-fit:contain;margin:12mm -${b.marginLeft}mm}.cover-foot{position:absolute;bottom:0;left:0;right:0;min-height:29mm;padding:8mm ${b.marginLeft}mm}.cover-foot .footer-banner{z-index:0}.cover-foot{isolation:isolate}.cover-foot .footer-banner{z-index:-1}h1,h2,h3,h4{font-family:${b.headingFont};color:${b.headingColor};line-height:1.2;break-after:avoid}h1{font-size:24pt;margin:0 0 9mm}h2{font-size:16pt;margin:7mm 0 3mm}h3{font-size:13pt;margin:5mm 0 2mm}p{margin:0 0 3mm}table{border-collapse:collapse;width:100%;margin:4mm 0;table-layout:fixed}th,td{border:1px solid #bbb;padding:2mm;vertical-align:top;overflow-wrap:anywhere}th{color:${b.headingColor};font-family:${b.headingFont};background:#f4f5f7}tr{break-inside:avoid}thead{display:table-header-group}li{margin:1mm 0}blockquote{border-left:3px solid ${b.accentColor};margin:4mm 0;padding-left:4mm}a{color:${b.accentColor}}.tv-content{overflow-wrap:anywhere}.tv-content:focus{outline:2px solid ${b.accentColor}}
.tv-editing .tv-page:not(.tv-cover){height:auto;min-height:297mm;overflow:visible}.tv-editing .tv-body{height:auto;overflow:visible}.tv-editing .tv-footer{position:relative;bottom:auto;left:0;right:0;margin-top:10mm;min-height:15mm}
@media print{@page{size:A4;margin:0}.tv-page-frame{width:210mm!important;height:297mm!important;margin:0;overflow:visible;break-after:page}.tv-page-frame:last-child{break-after:auto}.tv-page-frame>.tv-page{transform:none!important}body{background:white}.tv-page{margin:0;box-shadow:none;zoom:1!important}}
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
  // Measure rich-text prefixes in place so every caller uses the actual page layout.
  const split = (node) => {
    const original = node.cloneNode(true);
    const texts = [];
    const walker = doc.createTreeWalker(original, 4);
    let text;
    while ((text = walker.nextNode())) texts.push(text);
    const total = original.textContent.length;
    const rangeAt = (offset) => {
      const range = doc.createRange();
      range.selectNodeContents(original);
      for (const text of texts) {
        if (offset <= text.length) {
          // Keep UTF-16 surrogate pairs together.
          if (offset && /[\uD800-\uDBFF]/.test(text.data[offset - 1])) offset--;
          range.setEnd(text, offset);
          return range;
        }
        offset -= text.length;
      }
      return range;
    };
    let low = 1,
      high = total - 1,
      best = 0;
    while (low <= high) {
      const mid = (low + high) >> 1;
      node.replaceChildren(rangeAt(mid).cloneContents());
      if (fits()) {
        best = mid;
        low = mid + 1;
      } else high = mid - 1;
    }
    node.replaceChildren(...original.cloneNode(true).childNodes);
    if (!best) throw Error("Dit inhoudsblok past niet op A4.");
    const prefix = rangeAt(best);
    const rest = doc.createRange();
    rest.selectNodeContents(original);
    rest.setStart(prefix.endContainer, prefix.endOffset);
    const remainder = node.cloneNode(false);
    remainder.append(rest.cloneContents());
    node.replaceChildren(prefix.cloneContents());
    return remainder;
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
      if (node.tagName === "OL") {
        let number = Number(node.getAttribute("start") || 1);
        for (const part of parts) {
          number = Number(part.getAttribute("value") || number);
          part.value = number++;
        }
      }
      let fragment, holder;
      const startFragment = () => {
        fragment = node.cloneNode(false);
        if (node.tagName === "TABLE" && node.tHead)
          fragment.append(node.tHead.cloneNode(true));
        holder =
          node.tagName === "TABLE"
            ? fragment.appendChild(doc.createElement("tbody"))
            : fragment;
        target.append(fragment);
      };
      startFragment();
      for (let part of parts) {
        holder.append(part);
        if (fits()) continue;
        part.remove();
        if (!holder.children.length) fragment.remove();
        next();
        startFragment();
        holder.append(part);
        while (!fits()) {
          let remainder;
          if (node.tagName === "TABLE") {
            const originals = [...part.cells].map((cell) => cell.cloneNode(true));
            remainder = part.cloneNode(false);
            [...part.cells].forEach((cell) => cell.replaceChildren());
            for (let i = 0; i < originals.length; i++) {
              const cell = part.cells[i];
              cell.replaceChildren(...originals[i].cloneNode(true).childNodes);
              const tail = fits() ? cell.cloneNode(false) : split(cell);
              remainder.append(tail);
            }
          } else {
            remainder = split(part);
            remainder.style.listStyleType = "none";
          }
          next(false);
          startFragment();
          holder.append(remainder);
          part = remainder;
        }
      }
      continue;
    }
    if (target.childNodes.length) next();
    target.append(node);
    while (!fits()) {
      const remainder = split(node);
      next(false);
      target.append(remainder);
      node = remainder;
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
    let frame = page.parentElement;
    if (!frame.classList.contains("tv-page-frame")) {
      if (scale === 1) return;
      frame = doc.createElement("div");
      frame.className = "tv-page-frame";
      page.before(frame);
      frame.append(page);
    }
    // CSS zoom can reflow glyphs after pagination and clip text on narrow screens.
    frame.style.width = page.offsetWidth * scale + "px";
    frame.style.height = page.offsetHeight * scale + "px";
    page.style.transform = `scale(${scale})`;
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
