import { expect, it } from "vitest";
import { htmlToPlainText } from "../htmlToMarkdown";

it("separates adjacent note blocks without leaking styles or breaking inline words", () => {
  expect(htmlToPlainText('<style>.x{color:red}</style><h2>Kern</h2><p>Een <strong>besluit</strong> &amp; actie.</p><h2>Acties</h2><p>Alex begint.<br>Maandag.</p><script>alert(1)</script>'))
    .toBe("Kern\nEen besluit & actie.\nActies\nAlex begint.\nMaandag.");
});
