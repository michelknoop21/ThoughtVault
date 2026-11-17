import { standardBranding } from "./src/branding.js";
import { build } from "esbuild";
import { readFile, writeFile, mkdir } from "node:fs/promises";
const root = new URL(".", import.meta.url);
const image = async (file, mime) =>
  `data:${mime};base64,${(await readFile(new URL("assets/" + file, root))).toString("base64")}`;
const fonts = {};
const licenses = {};
for (const family of ["Carlito", "Caladea"])
  licenses[family] = await readFile(
    new URL("assets/" + family + "-OFL.txt", root),
    "utf8",
  );
for (const family of ["Carlito", "Caladea"])
  for (const face of ["Regular", "Bold", "Italic", "BoldItalic"])
    fonts[`${family}-${face}`] = await image(
      `${family}-${face}.ttf`,
      "font/ttf",
    );
const yinga = {
  schemaVersion: 1,
  id: "yinga",
  revision: 1,
  name: "Yinga",
  company: "Yinga",
  contact: "Stadhuisplein 345a · 5038 TH Tilburg\n013 580 23 41 · www.yinga.nl",
  layout: "compact",
  textColor: "#262626",
  headingColor: "#4F81BD",
  accentColor: "#CC0068",
  bodyFont: "Caladea",
  headingFont: "Carlito",
  fontSize: 11,
  lineHeight: 1.5,
  marginTop: 25,
  marginBottom: 25,
  marginLeft: 25,
  marginRight: 25,
  header: "Yinga · Notulen",
  footer: "www.yinga.nl",
  coverHeader: "Notulen",
  coverFooter: "Yinga · www.yinga.nl",
  pageNumbers: true,
  runningHeader: true,
  runningFooter: true,
  logo: await image("yinga-logo.png", "image/png"),
  coverBanner: await image("cover-banner.jpg", "image/jpeg"),
  headerBanner: await image("header-rule.png", "image/png"),
  footerBanner: await image("footer-banner.jpg", "image/jpeg"),
};
await mkdir(new URL("dist", root), { recursive: true });
await writeFile(
  new URL("src/bundled.json", root),
  JSON.stringify({ fonts, yinga, licenses }),
);
await writeFile(
  new URL("dist/Yinga.tvhuisstijl", root),
  JSON.stringify(yinga, null, 2),
);
await writeFile(
  new URL("dist/ThoughtVault.tvhuisstijl", root),
  JSON.stringify(standardBranding(), null, 2),
);
await build({
  entryPoints: [new URL("src/index.js", root).pathname],
  bundle: true,
  format: "iife",
  globalName: "TVDocument",
  outfile: new URL("dist/document.js", root).pathname,
  minify: true,
  legalComments: "eof",
});
await build({
  entryPoints: [new URL("src/index.js", root).pathname],
  bundle: true,
  format: "esm",
  outfile: new URL("dist/document.mjs", root).pathname,
  minify: true,
  legalComments: "eof",
});
await writeFile(
  new URL("dist/document.d.mts", root),
  await readFile(new URL("src/index.d.ts", root)),
);
await writeFile(
  new URL("../../docs/huisstijlen/Yinga.tvhuisstijl", root),
  JSON.stringify(yinga, null, 2),
);
await writeFile(
  new URL("dist/editor.html", root),
  `<!doctype html><html lang="nl"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Huisstijlen</title><body style="color-scheme:light dark;background:Canvas;color:CanvasText"><main id="editor"></main><script src="document.js"></script><script>window.brandingEditor=TVDocument.mountEditor(document.getElementById('editor'));</script></body></html>`,
);

await writeFile(
  new URL("dist/viewer.html", root),
  `<!doctype html><html lang="nl"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><body><script src="document.js"></script></body></html>`,
);

for (const family of ["Carlito", "Caladea"])
  await writeFile(
    new URL("dist/" + family + "-OFL.txt", root),
    await readFile(new URL("assets/" + family + "-OFL.txt", root)),
  );

await mkdir(new URL("../../windows/public/document-licenses", root), {
  recursive: true,
});
for (const family of ["Carlito", "Caladea"])
  await writeFile(
    new URL(
      "../../windows/public/document-licenses/" + family + "-OFL.txt",
      root,
    ),
    licenses[family],
  );

// Xcode folder resources keep their actual basename; use a real Document directory.
await mkdir(new URL("../../macos/Resources/Document", root), {
  recursive: true,
});
for (const file of [
  "document.js",
  "viewer.html",
  "editor.html",
  "Yinga.tvhuisstijl",
  "ThoughtVault.tvhuisstijl",
  "Carlito-OFL.txt",
  "Caladea-OFL.txt",
]) {
  await writeFile(
    new URL("../../macos/Resources/Document/" + file, root),
    await readFile(new URL("dist/" + file, root)),
  );
}
