import {
  Document,
  Packer,
  Paragraph,
  TextRun,
  Table,
  TableRow,
  TableCell,
  Header,
  Footer,
  ImageRun,
  HeadingLevel,
  PageNumber,
  WidthType,
  ExternalHyperlink,
  SectionType,
  LevelFormat,
  AlignmentType,
  VerticalMergeType,
} from "docx";
import {
  blankBranding,
  validateBranding,
  sanitizeContent,
} from "./branding.js";
import bundled from "./bundled.json";
const bytes = (uri) =>
  Uint8Array.from(atob(uri.split(",")[1]), (c) => c.charCodeAt(0));
const mm = (n) => Math.round((n * 1440) / 25.4);
export async function wordDocument({
  html,
  title = "",
  subtitle = "",
  branding = null,
}) {
  const b = branding
    ? validateBranding(
        typeof branding === "string" ? JSON.parse(branding) : branding,
      )
    : blankBranding();
  const doc = new DOMParser().parseFromString(
    sanitizeContent(html),
    "text/html",
  );
  const color = b.headingColor.slice(1);
  function runs(node, format = {}) {
    if (node.nodeType === 3)
      return [new TextRun({ text: node.textContent, ...format })];
    const tag = node.tagName;
    if (tag === "BR") return [new TextRun({ break: 1 })];
    const next = {
      ...format,
      ...(["B", "STRONG"].includes(tag) ? { bold: true } : {}),
      ...(["I", "EM"].includes(tag) ? { italics: true } : {}),
      ...(tag === "U" ? { underline: {} } : {}),
      ...(tag === "S" ? { strike: true } : {}),
      ...(tag === "SUP" ? { superScript: true } : {}),
      ...(tag === "SUB" ? { subScript: true } : {}),
    };
    const children = [...node.childNodes].flatMap((n) => runs(n, next));
    if (tag === "A" && node.getAttribute("href"))
      return [
        new ExternalHyperlink({ link: node.getAttribute("href"), children }),
      ];
    return children;
  }
  let listInstance = 0;
  function blocks(parent, level = 0, numbering = null) {
    const out = [];
    let inline = [];
    const flush = () => {
      if (inline.length) {
        out.push(new Paragraph({ children: inline }));
        inline = [];
      }
    };
    for (const n of parent.childNodes) {
      if (n.nodeType === 3) {
        if (n.textContent.trim()) inline.push(...runs(n));
        continue;
      }
      if (n.tagName === "TABLE") {
        flush();
        const rows = [...n.rows];
        const merges = new Map();
        out.push(
          new Table({
            width: { size: 100, type: WidthType.PERCENTAGE },
            rows: rows.map((row) => {
              const cells = [];
              let column = 0;
              const carry = () => {
                while (merges.has(column)) {
                  const m = merges.get(column);
                  cells.push(
                    new TableCell({
                      children: [new Paragraph("")],
                      columnSpan: m.span,
                      verticalMerge: VerticalMergeType.CONTINUE,
                    }),
                  );
                  if (--m.left === 0) merges.delete(column);
                  column += m.span;
                }
              };
              for (const cell of row.cells) {
                carry();
                const span = cell.colSpan || 1;
                const height = cell.rowSpan || 1;
                if (height > 1) merges.set(column, { left: height - 1, span });
                const children = blocks(cell);
                cells.push(
                  new TableCell({
                    children: children.length ? children : [new Paragraph("")],
                    columnSpan: span,
                    ...(height > 1
                      ? { verticalMerge: VerticalMergeType.RESTART }
                      : {}),
                    ...(cell.tagName === "TH"
                      ? { shading: { fill: "F4F5F7" } }
                      : {}),
                  }),
                );
                column += span;
              }
              carry();
              return new TableRow({
                tableHeader: row.parentElement.tagName === "THEAD",
                cantSplit: true,
                children: cells,
              });
            }),
          }),
        );
      } else if (["UL", "OL"].includes(n.tagName)) {
        flush();
        const instance = listInstance++;
        const ref = n.tagName === "OL" ? "ordered" : "bullet";
        out.push(
          ...blocks(n, level, {
            reference: ref,
            level: Math.min(level, 8),
            instance,
          }),
        );
      } else if (n.tagName === "LI") {
        flush();
        const copy = n.cloneNode(true);
        copy.querySelectorAll("ul,ol").forEach((x) => x.remove());
        out.push(new Paragraph({ children: runs(copy), numbering }));
        for (const list of n.children)
          if (["UL", "OL"].includes(list.tagName))
            out.push(...blocks({ childNodes: [list] }, level + 1));
      } else if (/^H[1-4]$/.test(n.tagName)) {
        flush();
        out.push(
          new Paragraph({
            heading: HeadingLevel["HEADING_" + n.tagName[1]],
            children: runs(n),
          }),
        );
      } else if (["DIV", "SECTION", "BLOCKQUOTE"].includes(n.tagName)) {
        flush();
        out.push(...blocks(n, level, numbering));
      } else if (n.tagName === "P") {
        flush();
        out.push(new Paragraph({ children: runs(n) }));
      } else inline.push(...runs(n));
    }
    flush();
    return out;
  }
  async function picture(uri, width, maxHeight) {
    if (!uri) return null;
    const img = new Image();
    img.src = uri;
    await img.decode();
    const scale = Math.min(
      width / img.naturalWidth,
      maxHeight / img.naturalHeight,
    );
    return new Paragraph({
      children: [
        new ImageRun({
          type: uri.startsWith("data:image/png") ? "png" : "jpg",
          data: bytes(uri),
          transformation: {
            width: img.naturalWidth * scale,
            height: img.naturalHeight * scale,
          },
        }),
      ],
    });
  }
  const width = ((210 - b.marginLeft - b.marginRight) * 96) / 25.4;
  const compact = (items) => items.filter(Boolean);
  const footer = async (cover) =>
    new Footer({
      children: compact([
        cover || b.runningFooter
          ? await picture(b.footerBanner, width, cover ? 90 : 36)
          : null,
        new Paragraph({
          children: [
            new TextRun(
              cover ? b.coverFooter : b.runningFooter ? b.footer : "",
            ),
            ...(b.pageNumbers && !cover
              ? [
                  new TextRun({
                    children: [
                      "  ",
                      PageNumber.CURRENT,
                      " / ",
                      PageNumber.TOTAL_PAGES,
                    ],
                  }),
                ]
              : []),
          ],
        }),
      ]),
    });
  const sectionProps = {
    page: {
      size: { width: mm(210), height: mm(297) },
      margin: {
        top: mm(b.marginTop),
        bottom: mm(b.marginBottom),
        left: mm(b.marginLeft),
        right: mm(b.marginRight),
        header: mm(4),
        footer: mm(4),
      },
    },
  };
  const sections = [];
  if (b.layout === "cover")
    sections.push({
      properties: sectionProps,
      children: compact([
        await picture(b.logo, 240, 110),
        new Paragraph(b.coverHeader),
        new Paragraph({ text: title, heading: HeadingLevel.TITLE }),
        subtitle ? new Paragraph(subtitle) : null,
        await picture(b.coverBanner, width, 230),
        new Paragraph(b.company),
        ...b.contact.split("\n").map((line) => new Paragraph(line)),
      ]),
      footers: { default: await footer(true) },
    });
  const children = blocks(doc.body);
  if (subtitle) children.unshift(new Paragraph(subtitle));
  if (title && !doc.querySelector("h1"))
    children.unshift(
      new Paragraph({ text: title, heading: HeadingLevel.HEADING_1 }),
    );
  sections.push({
    properties: { ...sectionProps, type: SectionType.NEXT_PAGE },
    children,
    headers: b.runningHeader
      ? {
          default: new Header({
            children: compact([
              await picture(b.logo, 100, 35),
              new Paragraph(b.header),
              await picture(b.headerBanner, width, 4),
            ]),
          }),
        }
      : undefined,
    footers:
      b.runningFooter || b.pageNumbers
        ? { default: await footer(false) }
        : undefined,
  });
  const fontNames = [...new Set([b.bodyFont, b.headingFont])];
  const result = new Document({
    creator: b.company || "ThoughtVault",
    title,
    fonts: fontNames.map((name) => ({
      name,
      data: bytes(bundled.fonts[name + "-Regular"]),
    })),
    styles: {
      default: {
        document: {
          run: {
            font: b.bodyFont,
            size: b.fontSize * 2,
            color: b.textColor.slice(1),
          },
          paragraph: {
            spacing: { after: 120, line: Math.round(240 * b.lineHeight) },
          },
        },
        heading1: {
          run: { font: b.headingFont, color, bold: true, size: 36 },
          paragraph: { keepNext: true },
        },
        heading2: {
          run: { font: b.headingFont, color, bold: true, size: 30 },
          paragraph: { keepNext: true },
        },
        heading3: {
          run: { font: b.headingFont, color, bold: true, size: 26 },
          paragraph: { keepNext: true },
        },
        title: { run: { font: b.headingFont, color, size: 48 } },
      },
    },
    numbering: {
      config: ["ordered", "bullet"].map((reference) => ({
        reference,
        levels: Array.from({ length: 9 }, (_, level) => ({
          level,
          format:
            reference === "ordered" ? LevelFormat.DECIMAL : LevelFormat.BULLET,
          text: reference === "ordered" ? `%${level + 1}.` : "•",
          alignment: AlignmentType.START,
          style: {
            paragraph: { indent: { left: 720 * (level + 1), hanging: 360 } },
          },
        })),
      })),
    },
    sections,
  });
  return new Uint8Array(await Packer.toArrayBuffer(result));
}
