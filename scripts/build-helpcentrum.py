#!/usr/bin/env python3
"""Build the static help centre (manual, search index, release notes).

Usage: scripts/build-helpcentrum.py <output-dir>

Sources: docs/handleiding/NN-slug.md (meta lines `groep:` and `samenvatting:`, then `# Title`),
docs/handleiding/media/*.webp and docs/RELEASE-NOTES.md. Output is one flat directory with
relative links only, so it can be served under any path prefix.
Fails on a broken internal link, a missing image or a release without a date line.
"""
import html, json, re, shutil, sys
from pathlib import Path

import markdown
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "docs" / "handleiding"
NOTES = ROOT / "docs" / "RELEASE-NOTES.md"
ASSETS = ROOT / "deploy" / "website" / "help"
PLATFORMS = {"macos": "Mac", "windows": "Windows", "ios": "iPhone en iPad"}
MONTHS = "januari februari maart april mei juni juli augustus september oktober november december".split()
errors = []


def slugify(text):
    text = re.sub(r"<[^>]+>", "", text).lower()
    text = re.sub(r"[^a-z0-9àáäèéëïóöüç]+", "-", text).strip("-")
    return text or "sectie"


def img_tag(src, alt):
    """<img> with intrinsic size, so the page does not jump while screenshots load."""
    path = SRC / src
    size = ""
    if path.is_file():
        with Image.open(path) as im:
            size = f' width="{im.width}" height="{im.height}"'
    return f'<img src="{html.escape(src)}" alt="{html.escape(alt)}"{size} loading="lazy">'


def render(md_text):
    """Markdown to HTML with platform blocks (`::: macos ios` ... `:::`) and figures."""
    def block(m):
        names = m.group(1).split()
        unknown = [n for n in names if n not in PLATFORMS]
        if unknown:
            errors.append(f"onbekend platform in blok: {' '.join(unknown)}")
        return f'<div class="pf" data-pf="{" ".join(names)}" markdown="1">\n\n{m.group(2).strip()}\n\n</div>'
    md_text = re.sub(r"^::: *([a-z ]+)\n(.*?)^:::\s*$", block, md_text, flags=re.S | re.M)
    out = markdown.markdown(md_text, extensions=["tables", "md_in_html", "sane_lists"])
    return re.sub(r'<p><img alt="([^"]*)" src="([^"]+)" ?/?></p>',
                  lambda m: f'<figure><div class="stage">{img_tag(m.group(2), html.unescape(m.group(1)))}</div><figcaption>{m.group(1)}</figcaption></figure>', out)


def add_heading_ids(body):
    """Give h2/h3 stable ids; return the body and the h2 outline."""
    seen, outline = {}, []
    def repl(m):
        level, inner = m.group(1), m.group(2)
        base = slugify(inner)
        seen[base] = seen.get(base, 0) + 1
        hid = base if seen[base] == 1 else f"{base}-{seen[base]}"
        if level == "2":
            outline.append((hid, re.sub(r"<[^>]+>", "", inner)))
        return f'<h{level} id="{hid}">{inner}</h{level}>'
    return re.sub(r"<h([23])>(.*?)</h\1>", repl, body), outline


def load_chapters():
    chapters = []
    for path in sorted(SRC.glob("[0-9][0-9]-*.md")):
        meta, lines = {}, path.read_text(encoding="utf-8").splitlines()
        while lines and re.match(r"^[a-z]+: ", lines[0]):
            key, _, value = lines.pop(0).partition(": ")
            meta[key] = value.strip()
        text = "\n".join(lines).strip()
        m = re.match(r"# (.+)\n", text)
        if not m or "groep" not in meta:
            errors.append(f"{path.name}: mist '# Titel' of de regel 'groep:'")
            continue
        body, outline = add_heading_ids(render(text[m.end():]))
        chapters.append({"slug": path.stem[3:], "title": m.group(1).strip(), "group": meta["groep"],
                         "summary": meta.get("samenvatting", ""), "image": meta.get("beeld", ""),
                         "body": body, "outline": outline})
    return chapters


def load_releases():
    text = NOTES.read_text(encoding="utf-8")
    releases = []
    for part in re.split(r"^## ", text, flags=re.M)[1:]:
        head, _, rest = part.partition("\n")
        m = re.match(r"(\d+\.\d+\.\d+) - (.+)", head.strip())
        d = re.match(r"\s*\*(\d{1,2}) ([a-z]+) (\d{4})((?: · [^*·]+)*)\*\s*\n", rest)
        if not m or not d or d.group(2) not in MONTHS:
            errors.append(f"RELEASE-NOTES.md: blok '{head.strip()[:50]}' mist 'versie - titel' of de cursieve datumregel")
            continue
        tags = [t.strip() for t in d.group(4).split("·") if t.strip()]
        releases.append({"version": m.group(1), "title": m.group(2).strip(), "date": f"{d.group(1)} {d.group(2)} {d.group(3)}",
                         "tags": tags, "body": render(rest[d.end():].strip())})
    return releases


ICON_SEARCH = '<svg viewBox="0 0 20 20" aria-hidden="true"><circle cx="9" cy="9" r="5.5"/><path d="m13.5 13.5 3.5 3.5"/></svg>'
ICON_NEXT = '<svg viewBox="0 0 20 20" aria-hidden="true"><path d="m8 5 5 5-5 5"/></svg>'


def search_form(big=False):
    return (f'<button type="button" class="search{" big" if big else ""}" data-open-search>{ICON_SEARCH}'
            '<span>Zoek op een functie of melding</span><kbd aria-hidden="true">/</kbd></button>')


def page(title, main, chapters, active="", rail=""):
    groups = {}
    for c in chapters:
        groups.setdefault(c["group"], []).append(c)
    nav = "".join(
        f'<div class="nav-group"><p>{html.escape(g)}</p>' + "".join(
            f'<a href="{c["slug"]}.html"{" aria-current=\"page\"" if c["slug"] == active else ""}>{html.escape(c["title"])}</a>'
            for c in items) + "</div>" for g, items in groups.items())
    switch = "".join(f'<button type="button" data-set-pf="{k}">{v}</button>' for k, v in PLATFORMS.items())
    return f"""<!doctype html>
<html lang="nl"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex,nofollow,noarchive"><meta name="referrer" content="no-referrer">
<meta name="color-scheme" content="light dark">
<title>{html.escape(title)} · ThoughtVault Help</title>
<link rel="icon" href="favicon.png"><link rel="stylesheet" href="help.css"><script src="help.js" defer></script></head>
<body class="{'is-start' if active == 'index' else ''}"><a class="skip" href="#inhoud">Naar de inhoud</a>
<header class="top"><div class="top-in"><a class="brand" href="index.html"><img src="thoughtvault-mark.png" alt="" width="28" height="31"><span>ThoughtVault</span><b>Help</b></a>
{search_form()}
<div class="pf-switch seg" role="group" aria-label="Toon uitleg voor">{switch}</div>
<button class="menu" type="button" aria-expanded="false" aria-controls="zijbalk">Inhoud</button></div></header>
<div class="shell"><nav id="zijbalk" class="side" aria-label="Handleiding"><a class="side-top" href="index.html"{' aria-current="page"' if active == 'index' else ''}>Overzicht</a>{nav}
<a class="side-top" href="release-notes.html"{' aria-current="page"' if active == 'release-notes' else ''}>Releasenotes</a></nav>
<main id="inhoud">{main}</main>{rail}</div>
<footer class="foot"><span>ThoughtVault is een product van Yinga</span><a href="release-notes.html">Releasenotes</a></footer></body></html>
"""


def check_links(name, body, pages, anchors):
    for href in re.findall(r'href="([^"]+)"', body):
        if re.match(r"(https?:|mailto:)", href):
            continue
        target, _, frag = href.partition("#")
        target = target or name
        if target not in pages:
            errors.append(f"{name}: link naar onbekende pagina '{href}'")
        elif frag and frag not in anchors.get(target, set()):
            errors.append(f"{name}: link naar onbekend anker '{href}'")
    for src in re.findall(r'<img src="([^"]+)"', body):
        if not (SRC / src).is_file():
            errors.append(f"{name}: afbeelding ontbreekt: {src}")


def main():
    out = Path(sys.argv[1])
    chapters, releases = load_chapters(), load_releases()
    pages = {f'{c["slug"]}.html' for c in chapters} | {"index.html", "release-notes.html"}
    anchors = {f'{c["slug"]}.html': set(re.findall(r' id="([^"]+)"', c["body"])) for c in chapters}
    anchors["release-notes.html"] = {f'v{r["version"]}' for r in releases}
    files, index = {}, []

    for i, c in enumerate(chapters):
        name = f'{c["slug"]}.html'
        check_links(name, c["body"], pages, anchors)
        prev = chapters[i - 1] if i else None
        nxt = chapters[i + 1] if i + 1 < len(chapters) else None
        pager = '<nav class="pager" aria-label="Volgende en vorige">' + (
            f'<a href="{prev["slug"]}.html"><small>Vorige</small>{html.escape(prev["title"])}</a>' if prev else "<span></span>") + (
            f'<a class="next" href="{nxt["slug"]}.html"><small>Volgende</small>{html.escape(nxt["title"])}</a>' if nxt else "") + "</nav>"
        rail = ('<aside class="rail" aria-label="Op deze pagina"><p>Op deze pagina</p>' + "".join(
            f'<a href="#{hid}">{html.escape(t)}</a>' for hid, t in c["outline"]) + "</aside>") if len(c["outline"]) > 1 else ""
        lead = f'<p class="lead">{html.escape(c["summary"])}</p>' if c["summary"] else ""
        article = f'<article class="doc sheet"><nav class="crumb" aria-label="Kruimelpad"><a href="index.html">Handleiding</a>{ICON_NEXT}<span>{html.escape(c["group"])}</span></nav><h1>{html.escape(c["title"])}</h1>{lead}{c["body"]}{pager}</article>'
        files[name] = page(c["title"], article, chapters, c["slug"], rail)
        # One search entry per h2 section, plus the chapter intro.
        parts = re.split(r'<h2 id="([^"]+)">(.*?)</h2>', c["body"])
        strip = lambda s: re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", s))).strip()
        index.append({"u": name, "c": c["title"], "t": c["title"], "x": strip(c["summary"] + " " + parts[0])[:600]})
        for j in range(1, len(parts), 3):
            index.append({"u": f"{name}#{parts[j]}", "c": c["title"], "t": strip(parts[j + 1]), "x": strip(parts[j + 2])[:600]})

    groups = {}
    for c in chapters:
        groups.setdefault(c["group"], []).append(c)
    latest = releases[0] if releases else None
    start = ('<section class="hero"><h1>Handleiding ThoughtVault</h1><p class="lead">Van opname tot notule, stap voor stap. '
             'Kies je apparaat en de uitleg en schermafbeeldingen passen zich aan.</p>' + search_form(big=True))
    if latest:
        start += (f'<a class="latest" href="release-notes.html#v{latest["version"]}"><b>Nieuw in {latest["version"]}</b>'
                  f'<span>{html.escape(latest["title"])}</span>{ICON_NEXT}</a>')
    start += "</section>"
    for c in [c for c in chapters if c["image"]]:
        if not (SRC / c["image"]).is_file():
            errors.append(f'{c["slug"]}: beeld ontbreekt: {c["image"]}')
        links = "".join(f'<li><a href="{c["slug"]}.html#{hid}">{html.escape(t)}{ICON_NEXT}</a></li>' for hid, t in c["outline"][:4])
        start += (f'<section class="feature"><a class="stage" href="{c["slug"]}.html">{img_tag(c["image"], "")}</a>'
                  f'<div><h2><a href="{c["slug"]}.html">{html.escape(c["title"])}</a></h2><p>{html.escape(c["summary"])}</p><ul>{links}</ul></div></section>')
    start += '<section class="sheet all"><h2>Alle onderwerpen</h2><div class="groups">' + "".join(
        f'<div><h3>{html.escape(g)}</h3><ul>' + "".join(
            f'<li><a href="{c["slug"]}.html">{html.escape(c["title"])}</a></li>' for c in items)
        + "</ul></div>" for g, items in groups.items()) + "</div></section>"
    files["index.html"] = page("Handleiding", start, chapters, "index")

    tags = sorted({t for r in releases for t in r["tags"]})
    notes = '<section class="notes sheet"><h1>Releasenotes</h1><p class="lead">Wat er per versie voor jou verandert, de nieuwste bovenaan.</p>'
    notes += '<div class="filter seg" role="group" aria-label="Filter op platform"><button type="button" data-tag="" aria-pressed="true">Alles</button>' + "".join(
        f'<button type="button" data-tag="{html.escape(t)}" aria-pressed="false">{html.escape(t)}</button>' for t in tags) + "</div>"
    for r in releases:
        check_links("release-notes.html", r["body"], pages, anchors)
        chips = "".join(f"<span>{html.escape(t)}</span>" for t in r["tags"])
        notes += (f'<article class="release" id="v{r["version"]}" data-tags="{html.escape("|".join(r["tags"]))}"><div class="when"><b>{r["version"]}</b>'
                  f'<time>{r["date"]}</time><div class="chips">{chips}</div></div><div class="what"><h2>{html.escape(r["title"])}</h2>{r["body"]}</div></article>')
        index.append({"u": f'release-notes.html#v{r["version"]}', "c": "Releasenotes", "t": f'{r["version"]}: {r["title"]}',
                      "x": re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", r["body"])))[:600]})
    files["release-notes.html"] = page("Releasenotes", notes + "</section>", chapters, "release-notes")

    if errors:
        sys.exit("Helpcentrum niet gebouwd:\n- " + "\n- ".join(errors))
    if out.exists():
        shutil.rmtree(out)
    (out / "media").mkdir(parents=True)
    for name, content in files.items():
        (out / name).write_text(content, encoding="utf-8")
    (out / "zoekindex.json").write_text(json.dumps(index, ensure_ascii=False), encoding="utf-8")
    for asset in ("help.css", "help.js"):
        shutil.copy(ASSETS / asset, out / asset)
    brand = ROOT / "docs" / "design" / "high-end-yinga" / "assets"
    for asset in ("thoughtvault-mark.png", "favicon.png"):
        shutil.copy(brand / asset, out / asset)
    for img in sorted((SRC / "media").glob("*.*")):
        shutil.copy(img, out / "media" / img.name)
    print(f"Helpcentrum gebouwd: {len(chapters)} hoofdstukken, {len(releases)} releases, {len(index)} zoekitems -> {out}")


if __name__ == "__main__":
    main()
