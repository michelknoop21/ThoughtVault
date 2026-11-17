import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { JSDOM } from "jsdom";
const dom = new JSDOM("", {
  runScripts: "outside-only",
  url: "http://127.0.0.1",
});
dom.window.eval(
  '"use strict";' +
    (await readFile(new URL("../dist/document.js", import.meta.url), "utf8")) +
    ";window.TVDocument=TVDocument;",
);
const api = dom.window.TVDocument;
const template = JSON.parse(
  await readFile(new URL("../dist/Yinga.tvhuisstijl", import.meta.url), "utf8"),
);
test("Yinga round trip embeds the four original assets", () => {
  const b = api.parseBranding(JSON.stringify(template));
  assert.equal(b.bodyFont, "Caladea");
  assert.equal(b.headingFont, "Carlito");
  for (const key of ["logo", "coverBanner", "headerBanner", "footerBanner"])
    assert.match(b[key], /^data:image\/(png|jpeg);base64,/);
  assert.equal(
    JSON.stringify(api.parseBranding(JSON.stringify(b))),
    JSON.stringify(b),
  );
});
test("invalid, future and oversized imports fail closed", () => {
  for (const patch of [
    { schemaVersion: 2 },
    { layout: "arbitrary" },
    { bodyFont: "remote-font" },
    { textColor: "red;display:none" },
    { fontSize: Infinity },
    { lineHeight: 0 },
    { revision: 0 },
    { logo: "https://example.com/logo.png" },
    { logo: "data:image/svg+xml;base64,PHN2Zz4=" },
    { logo: "data:image/png;base64,aGVsbG8=" },
    { name: "" },
    { pageNumbers: "yes" },
  ])
    assert.throws(() => api.validateBranding({ ...template, ...patch }));
  assert.throws(() => api.parseBranding(" ".repeat(api.MAX_FILE_BYTES + 1)));
});
test("library validation and immutable applied snapshots", () => {
  const b = api.validateBranding(template);
  const snapshot = JSON.stringify(b);
  const library = api.validateLibrary({
    schemaVersion: 1,
    defaultId: b.id,
    styles: [b],
  });
  library.styles[0].name = "Updated";
  library.styles.splice(0, 1);
  assert.equal(api.parseBranding(snapshot).name, "Yinga");
  assert.throws(() =>
    api.validateLibrary({ schemaVersion: 1, defaultId: "absent", styles: [] }),
  );
  assert.throws(() =>
    api.validateLibrary({ schemaVersion: 1, defaultId: null, styles: [b, b] }),
  );
});
test("rendering sanitizes content, keeps paper colors and embeds licensed fonts", () => {
  const rendered = api.renderDocument({
    title: "<script>Bad</script>",
    html: '<h2>Besluiten</h2><p>Één &amp; twee</p><img src="https://example.com/x"><script>alert(1)</script><a href="javascript:evil()">link</a>',
    branding: template,
  });
  const document = new JSDOM(rendered).window.document;
  assert.equal(document.querySelectorAll("script").length, 0);
  assert.equal(document.querySelectorAll('img[src^="https:"]').length, 0);
  assert.equal(document.querySelector("a").hasAttribute("href"), false);
  assert.equal(document.title, "<script>Bad</script>");
  assert.ok(
    document.styleSheets[0].cssRules.length > 30,
    "all document CSS must parse",
  );
  assert.match(rendered, /data:font\/ttf;base64/);
  assert.match(rendered, /color-scheme:light/);
  assert.match(rendered, /@page\{size:A4;margin:0\}/);
  assert.equal(document.querySelectorAll("[contenteditable]").length, 0);
});
test("editable content excludes the document assets", () => {
  const document = new JSDOM(
    api.renderDocument({
      html: "<p>Editable</p>",
      title: "",
      branding: template,
      editable: true,
    }),
  ).window.document;
  assert.equal(document.querySelectorAll("[contenteditable]").length, 1);
  assert.equal(document.querySelector("[contenteditable] img"), null);
});

test("editor creates textareas in strict ES-module mode", () => {
  dom.window.ResizeObserver = class {
    observe() {}
    disconnect() {}
  };
  const root = dom.window.document.createElement("main");
  dom.window.document.body.append(root);
  const editor = api.mountEditor(root, {
    library: { schemaVersion: 1, defaultId: null, styles: [template] },
  });
  assert.equal(
    root.querySelector('[aria-label="Contactgegevens"]').tagName,
    "TEXTAREA",
  );
  assert.equal(
    root.querySelector('[aria-label="Naam huisstijl"]').value,
    "Yinga",
  );
  editor.destroy();
  root.remove();
});

test("Apple JSON omitting an unset default remains compatible", () => {
  const library = api.validateLibrary({ schemaVersion: 1, styles: [] });
  assert.equal(library.defaultId, null);
  assert.equal(library.styles.length, 0);
});


test("editor keeps keyboard focus across save, default and duplicate redraws", async () => {
  const root = dom.window.document.createElement("main");
  dom.window.document.body.append(root);
  const editor = api.mountEditor(root, {
    library: { schemaVersion: 1, defaultId: null, styles: [template] },
    onSave: async () => {},
  });
  for (const label of ["Opslaan", "Standaard maken", "Dupliceren"]) {
    const button = [...root.querySelectorAll("button")].find(b => b.textContent === label);
    button.focus();
    button.click();
    await new Promise(resolve => setTimeout(resolve, 20));
    assert.equal(dom.window.document.activeElement.textContent, label);
    assert.ok(dom.window.document.activeElement.isConnected);
  }
  editor.destroy();
  root.remove();
});
