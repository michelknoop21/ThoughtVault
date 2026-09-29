import { expect, it } from "vitest";
import { prepareNotuleHtml } from "../notulePresentation";

it("uses app styling, one title, and keeps the selected template's section order", () => {
  const html = `<style>body{background:red}</style><header><h1>Planning</h1></header>
    <section><h2>Ideeën</h2><p style="color:red">Details</p></section>
    <section><h2>Open vragen</h2><p>Budget</p></section>
    <section><h2>Vervolg</h2><p>Werk uit</p></section>`;
  const prepared = prepareNotuleHtml(html, "Planning");
  expect(prepared).not.toContain("background:red");
  expect(prepared).not.toContain("color:red");
  expect(prepared).not.toContain("<h1>");
  expect(prepared.indexOf("Ideeën")).toBeLessThan(prepared.indexOf("Open vragen"));
  expect(prepared.indexOf("Open vragen")).toBeLessThan(prepared.indexOf("Vervolg"));
});

it("never repeats generated h1 titles inside a document", () => {
  const prepared = prepareNotuleHtml("<h1>Modeltitel</h1><h1>Extra titel</h1><p>Inhoud</p>", "Opname");
  expect(prepared).not.toContain("<h1>");
  expect(prepared).toContain("Inhoud");
});
