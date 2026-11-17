import {
  blankBranding,
  validateBranding,
  validateLibrary,
  parseBranding,
  validateImage,
  validateAssets,
  MAX_FILE_BYTES,
  MAX_IMAGE_BYTES,
  sample,
} from "./branding.js";
import { renderDocument, paginate, fitDocument, bundled } from "./render.js";
const clone = (value) => JSON.parse(JSON.stringify(value));
const css = `.tv-editor{box-sizing:border-box;width:100%;font:14px system-ui;color:inherit;max-width:1500px;margin:auto;padding:20px}.tv-editor *{box-sizing:border-box}.tv-editor h2{margin:0 0 8px}.tv-editor nav,.tv-editor .actions{display:flex;flex-wrap:wrap;gap:8px;margin:12px 0}.tv-editor button,.tv-editor select,.tv-editor input,.tv-editor textarea{font:inherit;border:1px solid #89898f;border-radius:6px;padding:8px;background:Canvas;color:CanvasText;min-height:36px}.tv-editor button{cursor:pointer}.tv-editor button:focus-visible,.tv-editor input:focus-visible,.tv-editor select:focus-visible{outline:3px solid #7830d8;outline-offset:2px}.tv-editor button:disabled{opacity:.5;cursor:default}.tv-editor label{display:flex;flex-direction:column;gap:5px;margin:12px 0}.tv-editor .check{flex-direction:row;align-items:center}.tv-editor fieldset{border:1px solid #aaa5;border-radius:8px;margin:16px 0;padding:12px}.tv-editor legend{font-weight:600}.tv-editor .layout{display:grid;grid-template-columns:minmax(260px,360px) minmax(0,1fr);gap:24px}.tv-editor .preview{min-width:0;position:sticky;top:8px;align-self:start;background:#e8e8ec}.tv-editor iframe{display:block;border:0;width:100%;height:780px;background:white}.tv-editor .status{min-height:24px}.tv-editor .mobile-toggle{display:none}.tv-editor .asset img{display:block;max-width:150px;max-height:60px;background:white}.tv-editor input[type=file]{width:100%}.tv-editor input[type=color]{width:100%;padding:3px}.tv-editor .hint{font-size:13px;opacity:.8}.tv-editor [hidden]{display:none!important}@media(max-width:700px){.tv-editor{padding:12px}.tv-editor .layout{display:block}.tv-editor .mobile-toggle{display:flex}.tv-editor[data-pane=edit] .preview,.tv-editor[data-pane=preview] .fields{display:none}.tv-editor .preview{position:static}.tv-editor iframe{height:750px}}`;
export function mountEditor(
  root,
  {
    library = { schemaVersion: 1, defaultId: null, styles: [] },
    onSave,
    onExport,
  } = {},
) {
  let saved = validateLibrary(library),
    selected = saved.styles[0]?.id || "",
    draft = null,
    busy = false,
    previewGeneration = 0;
  root.className = "tv-editor";
  root.dataset.pane = "edit";
  const sheet = document.createElement("style");
  sheet.textContent = css;
  root.append(sheet);
  const heading = document.createElement("h2");
  heading.textContent = "Huisstijlen";
  root.append(heading);
  const intro = document.createElement("p");
  intro.textContent =
    "Maak je notulen herkenbaar. Eerdere notulen houden hun toegepaste versie.";
  root.append(intro);
  const nav = document.createElement("nav");
  nav.setAttribute("aria-label", "Huisstijlen beheren");
  root.append(nav);
  const picker = document.createElement("select");
  picker.setAttribute("aria-label", "Huisstijl kiezen");
  nav.append(picker);
  const status = document.createElement("p");
  status.className = "status";
  status.setAttribute("role", "status");
  root.append(status);
  const panes = document.createElement("nav");
  panes.className = "mobile-toggle";
  root.append(panes);
  for (const [text, value] of [
    ["Instellingen", "edit"],
    ["Voorbeeld", "preview"],
  ]) {
    const tab = button(panes, text, () => {
      root.dataset.pane = value;
      for (const button of panes.children)
        button.setAttribute("aria-pressed", String(button === tab));
    });
    tab.setAttribute("aria-pressed", String(value === "edit"));
  }
  const layout = document.createElement("div");
  layout.className = "layout";
  root.append(layout);
  const fields = document.createElement("div");
  fields.className = "fields";
  layout.append(fields);
  const preview = document.createElement("div");
  preview.className = "preview";
  layout.append(preview);
  const frame = document.createElement("iframe");
  frame.title = "Voorbeeldnotule in deze huisstijl";
  frame.setAttribute("sandbox", "allow-same-origin");
  preview.append(frame);
  function button(parent, text, action) {
    const b = document.createElement("button");
    b.type = "button";
    b.textContent = text;
    b.onclick = () => perform(action);
    parent.append(b);
    return b;
  }
  async function perform(action) {
    if (busy) return;
    status.textContent = "";
    try {
      await action();
    } catch (e) {
      status.textContent = e.message || String(e);
    }
  }
  async function persist(next) {
    busy = true;
    root.querySelectorAll("button").forEach((b) => (b.disabled = true));
    try {
      next = validateLibrary(next);
      for (const b of next.styles) await validateAssets(b);
      if (onSave) await onSave(next);
      else if (window.webkit?.messageHandlers?.branding) await nativeSave(next);
      saved = clone(next);
      status.textContent = "Opgeslagen";
    } finally {
      busy = false;
      root.querySelectorAll("button").forEach((b) => (b.disabled = false));
    }
  }
  let nativeResult;
  function nativeSave(value) {
    return new Promise((resolve, reject) => {
      nativeResult = { resolve, reject };
      window.webkit.messageHandlers.branding.postMessage({
        type: "save",
        library: value,
      });
    });
  }
  button(nav, "Nieuwe huisstijl", () => {
    draft = { ...blankBranding(), id: crypto.randomUUID() };
    selected = draft.id;
    draw();
  });
  button(nav, "Yinga toevoegen", async () => {
    const current = saved.styles.find((b) => b.id === "yinga");
    if (current) {
      selected = current.id;
      draft = clone(current);
      draw();
      return;
    }
    const b = clone(bundled.yinga);
    await persist({ ...saved, styles: [...saved.styles, b] });
    selected = b.id;
    draft = b;
    draw();
  });
  button(nav, "Importeren", () => input.click());
  const input = document.createElement("input");
  input.type = "file";
  input.accept = ".tvhuisstijl,application/json";
  input.hidden = true;
  nav.append(input);
  input.onchange = () =>
    perform(async () => {
      const file = input.files[0];
      if (!file) return;
      if (file.size > MAX_FILE_BYTES)
        throw Error("Het bestand is groter dan 12 MB.");
      let b = parseBranding(await file.text());
      if (b.id === "thoughtvault") b = { ...b, id: crypto.randomUUID() };
      const existing = saved.styles.find((style) => style.id === b.id);
      if (
        existing &&
        !confirm(
          "Deze huisstijl bestaat al. Vervangen door de geïmporteerde versie? Eerdere notulen blijven ongewijzigd.",
        )
      )
        return;
      const imported = existing
        ? { ...b, revision: Math.max(existing.revision, b.revision) + 1 }
        : b;
      await persist({
        ...saved,
        styles: [
          ...saved.styles.filter((style) => style.id !== b.id),
          imported,
        ],
      });
      selected = imported.id;
      draft = imported;
      draw();
      input.value = "";
    });
  picker.onchange = () => {
    selected = picker.value;
    draft = clone(saved.styles.find((b) => b.id === selected));
    draw();
  };
  function field(
    parent,
    label,
    key,
    { type = "text", min, max, options } = {},
  ) {
    const l = document.createElement("label");
    l.textContent = label;
    parent.append(l);
    const el = document.createElement(
      options
        ? "select"
        : [
              "contact",
              "header",
              "footer",
              "coverHeader",
              "coverFooter",
            ].includes(key)
          ? "textarea"
          : "input",
    );
    if (options)
      for (const [value, text] of options) {
        const option = document.createElement("option");
        option.value = value;
        option.textContent = text;
        el.append(option);
      }
    else if (el.tagName === "INPUT") el.type = type;
    if (min !== undefined) {
      el.min = min;
      el.max = max;
      el.step = key === "fontSize" ? 0.5 : 0.1;
    }
    if (type === "checkbox") {
      l.className = "check";
      el.checked = draft[key];
    } else el.value = draft[key];
    el.setAttribute("aria-label", label);
    l.append(el);
    el.oninput = () => {
      draft[key] =
        type === "checkbox"
          ? el.checked
          : type === "number"
            ? Number(el.value)
            : el.value;
      updatePreview();
    };
  }
  function group(title) {
    const f = document.createElement("fieldset");
    const legend = document.createElement("legend");
    legend.textContent = title;
    f.append(legend);
    fields.append(f);
    return f;
  }
  function asset(parent, label, key) {
    const l = document.createElement("label");
    l.className = "asset";
    l.textContent = label + " (PNG/JPEG, maximaal 2 MB)";
    parent.append(l);
    if (draft[key]) {
      const img = document.createElement("img");
      img.src = draft[key];
      img.alt = label;
      l.append(img);
    }
    const el = document.createElement("input");
    el.type = "file";
    el.accept = "image/png,image/jpeg";
    el.setAttribute("aria-label", label);
    l.append(el);
    el.onchange = () =>
      perform(async () => {
        const file = el.files[0];
        if (!file) return;
        if (file.size > MAX_IMAGE_BYTES)
          throw Error("De afbeelding is groter dan 2 MB.");
        const uri = await new Promise((resolve, reject) => {
          const reader = new FileReader();
          reader.onload = () => resolve(reader.result);
          reader.onerror = reject;
          reader.readAsDataURL(file);
        });
        validateImage(uri);
        const image = new Image();
        image.src = uri;
        await image.decode();
        if (
          image.naturalWidth > 10000 ||
          image.naturalHeight > 10000 ||
          image.naturalWidth * image.naturalHeight > 25000000
        )
          throw Error(
            "De afbeelding heeft te veel pixels. Gebruik maximaal 25 megapixels.",
          );
        draft[key] = uri;
        draw();
      });
    if (draft[key])
      button(parent, label + " verwijderen", () => {
        draft[key] = "";
        draw();
      });
  }
  async function updatePreview() {
    if (!frame.clientWidth) return;
    const generation = ++previewGeneration;
    try {
      const html = renderDocument({ ...sample, branding: draft });
      frame.onload = () =>
        perform(async () => {
          if (generation !== previewGeneration) return;
          await paginate(frame.contentDocument);
          fitDocument(frame.contentDocument);
        });
      frame.srcdoc = html;
    } catch (e) {
      status.textContent = e.message;
    }
  }
  function draw() {
    picker.replaceChildren();
    for (const b of saved.styles) {
      const option = document.createElement("option");
      option.value = b.id;
      option.textContent =
        b.name + (b.id === saved.defaultId ? " (standaard)" : "");
      picker.append(option);
    }
    if (draft && !saved.styles.some((b) => b.id === draft.id)) {
      const option = document.createElement("option");
      option.value = draft.id;
      option.textContent = draft.name + " (nog niet opgeslagen)";
      picker.append(option);
    }
    picker.value = selected;
    fields.replaceChildren();
    if (!draft) {
      const empty = document.createElement("p");
      empty.textContent =
        "Voeg de kant-en-klare Yinga-huisstijl toe of maak je eigen huisstijl.";
      fields.append(empty);
      updatePreview();
      return;
    }
    const details = group("Bedrijf");
    field(details, "Naam huisstijl", "name");
    field(details, "Bedrijfsnaam", "company");
    field(details, "Contactgegevens", "contact");
    const design = group("Opmaak");
    field(design, "Indeling", "layout", {
      options: [
        ["compact", "Compact"],
        ["cover", "Met voorblad"],
      ],
    });
    for (const [key, label] of [
      ["textColor", "Tekstkleur"],
      ["headingColor", "Kopkleur"],
      ["accentColor", "Accentkleur"],
    ])
      field(design, label, key, { type: "color" });
    for (const [key, label] of [
      ["bodyFont", "Lettertype tekst"],
      ["headingFont", "Lettertype koppen"],
    ])
      field(design, label, key, {
        options: [
          ["Carlito", "Carlito"],
          ["Caladea", "Caladea"],
        ],
      });
    field(design, "Lettergrootte (pt)", "fontSize", {
      type: "number",
      min: 9,
      max: 20,
    });
    field(design, "Regelafstand", "lineHeight", {
      type: "number",
      min: 1,
      max: 2.5,
    });
    const margins = group("Paginamarges");
    for (const [key, label] of [
      ["marginTop", "Boven"],
      ["marginBottom", "Onder"],
      ["marginLeft", "Links"],
      ["marginRight", "Rechts"],
    ])
      field(margins, label + " (mm)", key, {
        type: "number",
        min: key === "marginLeft" || key === "marginRight" ? 10 : 15,
        max: 40,
      });
    const cover = group("Voorblad");
    field(cover, "Koptekst voorblad", "coverHeader");
    field(cover, "Voettekst voorblad", "coverFooter");
    asset(cover, "Voorbladbanner", "coverBanner");
    const recurring = group("Terugkerende kop en voet");
    asset(recurring, "Logo", "logo");
    asset(recurring, "Kopbanner", "headerBanner");
    asset(recurring, "Voetbanner", "footerBanner");
    field(recurring, "Koptekst", "header");
    field(recurring, "Voettekst", "footer");
    for (const [key, label] of [
      ["runningHeader", "Koptekst op iedere inhoudspagina"],
      ["runningFooter", "Voettekst op iedere inhoudspagina"],
      ["pageNumbers", "Paginanummers"],
    ])
      field(recurring, label, key, { type: "checkbox" });
    const actions = document.createElement("nav");
    actions.className = "actions";
    fields.prepend(actions);
    button(actions, "Opslaan", async () => {
      const previous = saved.styles.find((b) => b.id === draft.id);
      const b = validateBranding({
        ...draft,
        revision: (previous?.revision || 0) + 1,
      });
      await persist({
        ...saved,
        styles: [...saved.styles.filter((s) => s.id !== b.id), b],
      });
      draft = clone(b);
      draw();
    });
    button(actions, "Dupliceren", () => {
      draft = {
        ...clone(draft),
        id: crypto.randomUUID(),
        revision: 1,
        name: draft.name + " (kopie)",
      };
      selected = draft.id;
      draw();
    });
    button(actions, "Standaard maken", async () => {
      if (!saved.styles.some((b) => b.id === draft.id))
        throw Error("Sla de huisstijl eerst op.");
      await persist({ ...saved, defaultId: draft.id });
      draw();
    });
    button(actions, "Standaard ThoughtVault", async () => {
      await persist({ ...saved, defaultId: null });
      draw();
    });
    button(actions, "Exporteren", async () => {
      const b = validateBranding(draft);
      const payload = {
        name: b.name + ".tvhuisstijl",
        text: JSON.stringify(b, null, 2),
      };
      if (onExport) await onExport(payload);
      else if (window.webkit?.messageHandlers?.branding)
        window.webkit.messageHandlers.branding.postMessage({
          type: "export",
          ...payload,
        });
      else {
        const a = document.createElement("a");
        a.href = URL.createObjectURL(
          new Blob([payload.text], { type: "application/json" }),
        );
        a.download = payload.name;
        a.click();
        setTimeout(() => URL.revokeObjectURL(a.href), 1000);
      }
    });
    button(actions, "Verwijderen", async () => {
      if (
        !confirm("Huisstijl verwijderen? Eerdere notulen behouden hun versie.")
      )
        return;
      await persist({
        ...saved,
        defaultId: saved.defaultId === draft.id ? null : saved.defaultId,
        styles: saved.styles.filter((s) => s.id !== draft.id),
      });
      selected = saved.styles[0]?.id || "";
      draft = selected ? clone(saved.styles[0]) : null;
      draw();
    });
    updatePreview();
  }
  if (selected) draft = clone(saved.styles[0]);
  draw();
  const resize = new ResizeObserver(() => {
    updatePreview();
  });
  resize.observe(preview);
  return {
    loadLibrary(value) {
      saved = validateLibrary(value);
      selected = saved.styles[0]?.id || "";
      draft = selected ? clone(saved.styles[0]) : null;
      draw();
    },
    saved(error) {
      if (error) nativeResult?.reject(Error(error));
      else nativeResult?.resolve();
      nativeResult = null;
    },
    destroy() {
      resize.disconnect();
      root.replaceChildren();
    },
  };
}
