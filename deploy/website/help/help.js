// Help centre: platform switch, search palette, mobile contents drawer, release filter, image viewer.
(() => {
  const root = document.documentElement, $ = (s, el = document) => el.querySelector(s), $$ = (s, el = document) => [...el.querySelectorAll(s)];
  const store = { get: k => { try { return localStorage.getItem(k); } catch { return null; } },
                  set: (k, v) => { try { localStorage.setItem(k, v); } catch {} } };
  const esc = s => s.replace(/[&<>"]/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));

  // Segmented controls: the thumb slides to the pressed button.
  const press = (group, button) => {
    const buttons = $$("button", group);
    buttons.forEach(b => b.setAttribute("aria-pressed", b === button));
    group.style.setProperty("--n", buttons.length); group.style.setProperty("--i", buttons.indexOf(button));
  };

  // Platform: explicit ?platform= (the app's help button), then the saved choice, then the device.
  const PF = ["macos", "windows", "ios"];
  const guess = /iPhone|iPad/.test(navigator.userAgent) || (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1) ? "ios"
    : /Win/.test(navigator.platform) ? "windows" : "macos";
  const asked = new URLSearchParams(location.search).get("platform");
  const side = $(".side");
  const mobileSwitch = $(".pf-switch").cloneNode(true); mobileSwitch.classList.add("mobile-pf"); side.prepend(mobileSwitch);
  const setPlatform = pf => { root.dataset.pf = pf; $$(".pf-switch").forEach(g => press(g, $(`[data-set-pf=${pf}]`, g))); };
  setPlatform(PF.includes(asked) ? asked : PF.includes(store.get("tv-help-pf")) ? store.get("tv-help-pf") : guess);
  if (PF.includes(asked)) store.set("tv-help-pf", asked);
  $$("[data-set-pf]").forEach(b => b.addEventListener("click", () => { setPlatform(b.dataset.setPf); store.set("tv-help-pf", b.dataset.setPf); }));

  // Mobile contents: a bottom drawer with a scrim.
  const menu = $(".menu"), scrim = document.body.appendChild(Object.assign(document.createElement("div"), { className: "scrim" }));
  const drawer = open => { menu.setAttribute("aria-expanded", open); side.classList.toggle("open", open); scrim.classList.toggle("open", open); };
  menu.addEventListener("click", () => drawer(menu.getAttribute("aria-expanded") !== "true"));
  scrim.addEventListener("click", () => drawer(false));

  // Search palette. Every word must occur; a hit in the title outranks one in the text.
  const palette = document.body.appendChild(document.createElement("dialog"));
  palette.className = "palette"; palette.setAttribute("aria-label", "Zoeken in de handleiding");
  palette.innerHTML = `<label>${$("[data-open-search] svg").outerHTML}<input type="search" placeholder="Zoek op een functie of melding" autocomplete="off" aria-controls="hits"></label>
    <div class="hits" id="hits" role="listbox"></div>
    <footer><span><kbd>↑</kbd><kbd>↓</kbd> kiezen</span><span><kbd>↵</kbd> openen</span><span><kbd>esc</kbd> sluiten</span></footer>`;
  const input = $("input", palette), hits = $(".hits", palette);
  let index, selected = 0;
  const select = i => {
    const items = $$("a", hits); if (!items.length) return;
    selected = (i + items.length) % items.length;
    items.forEach((a, n) => a.setAttribute("aria-selected", n === selected));
    items[selected].scrollIntoView({ block: "nearest" });
  };
  const render = async () => {
    index ??= await fetch("zoekindex.json").then(r => r.json()).catch(() => []);
    const words = input.value.toLowerCase().split(/\s+/).filter(w => w.length > 1);
    let found;
    if (!words.length) found = index.filter(e => !e.u.includes("#")).slice(0, 7);
    else found = index.map(e => {
      const title = e.t.toLowerCase(), text = e.x.toLowerCase();
      if (!words.every(w => title.includes(w) || text.includes(w))) return null;
      return { e, score: words.reduce((s, w) => s + (title.includes(w) ? 10 : 1), 0) };
    }).filter(Boolean).sort((a, b) => b.score - a.score).slice(0, 9).map(h => h.e);
    if (!found.length) { hits.innerHTML = `<div class="empty"><b>Niets gevonden voor "${esc(input.value)}"</b>Probeer een ander woord, bijvoorbeeld de naam van een knop of scherm.</div>`; return; }
    const row = e => `<a role="option" href="${esc(e.u)}"><b>${esc(e.t)}</b><span>${esc(e.c === e.t ? e.x : e.c + " · " + e.x)}</span></a>`;
    const manual = found.filter(e => e.c !== "Releasenotes"), notes = found.filter(e => e.c === "Releasenotes");
    hits.innerHTML = (manual.length ? `<p>${words.length ? "Handleiding" : "Hoofdstukken"}</p>` + manual.map(row).join("") : "")
      + (notes.length ? "<p>Releasenotes</p>" + notes.map(row).join("") : "");
    select(0);
  };
  const openSearch = () => { if (palette.open) return; input.value = ""; palette.showModal(); render(); };
  $$("[data-open-search]").forEach(b => b.addEventListener("click", openSearch));
  input.addEventListener("input", render);
  input.addEventListener("keydown", e => {
    if (e.key === "ArrowDown") { e.preventDefault(); select(selected + 1); }
    else if (e.key === "ArrowUp") { e.preventDefault(); select(selected - 1); }
    else if (e.key === "Enter") { e.preventDefault(); $$("a", hits)[selected]?.click(); }
  });
  hits.addEventListener("pointermove", e => { const a = e.target.closest("a"); if (a) select($$("a", hits).indexOf(a)); });
  hits.addEventListener("click", e => { if (e.target.closest("a")) palette.close(); });
  palette.addEventListener("click", e => { if (e.target === palette) palette.close(); });
  document.addEventListener("keydown", e => {
    const typing = /INPUT|TEXTAREA/.test(document.activeElement.tagName);
    if ((e.key === "/" && !typing) || (e.key.toLowerCase() === "k" && (e.metaKey || e.ctrlKey))) { e.preventDefault(); openSearch(); }
    if (e.key === "Escape") drawer(false);
  });

  // Release filter.
  const filter = $(".filter");
  if (filter) {
    press(filter, $("button", filter));
    $$("button", filter).forEach(b => b.addEventListener("click", () => {
      press(filter, b);
      $$(".release").forEach(r => { r.hidden = !!b.dataset.tag && !r.dataset.tags.split("|").includes(b.dataset.tag); });
    }));
  }

  // "Op deze pagina": mark the section in view.
  const railLinks = $$(".rail a");
  if (railLinks.length) {
    const byId = Object.fromEntries(railLinks.map(a => [a.hash.slice(1), a]));
    const spy = new IntersectionObserver(entries => entries.forEach(en => {
      if (en.isIntersecting) { railLinks.forEach(a => a.classList.remove("on")); byId[en.target.id]?.classList.add("on"); }
    }), { rootMargin: "-15% 0px -70% 0px" });
    $$(".doc h2[id]").forEach(h => spy.observe(h));
  }

  // Screenshots open full size.
  const viewer = document.body.appendChild(document.createElement("dialog")); viewer.className = "viewer";
  viewer.addEventListener("click", () => viewer.close());
  $$("figure .stage img").forEach(img => img.addEventListener("click", () => {
    viewer.innerHTML = `<img src="${esc(img.getAttribute("src"))}" alt="${esc(img.alt)}">`; viewer.showModal();
  }));
})();
