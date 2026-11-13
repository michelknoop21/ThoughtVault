// Help centre: platform switch, search, mobile contents, release filter.
(() => {
  const root = document.documentElement;
  const store = { get: k => { try { return localStorage.getItem(k); } catch { return null; } },
                  set: (k, v) => { try { localStorage.setItem(k, v); } catch {} } };

  // Platform: explicit ?platform= (used by the app's help button), then the saved choice, then the device.
  const guess = /iPhone|iPad/.test(navigator.userAgent) || (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1) ? "ios"
    : /Win/.test(navigator.platform) ? "windows" : "macos";
  const asked = new URLSearchParams(location.search).get("platform");
  const setPlatform = pf => {
    root.dataset.pf = pf;
    document.querySelectorAll("[data-set-pf]").forEach(b => b.setAttribute("aria-pressed", b.dataset.setPf === pf));
  };
  const valid = pf => ["macos", "windows", "ios"].includes(pf);
  setPlatform(valid(asked) ? asked : valid(store.get("tv-help-pf")) ? store.get("tv-help-pf") : guess);
  if (valid(asked)) store.set("tv-help-pf", asked);
  document.querySelectorAll("[data-set-pf]").forEach(b => b.addEventListener("click", () => { setPlatform(b.dataset.setPf); store.set("tv-help-pf", b.dataset.setPf); }));

  const menu = document.querySelector(".menu"), side = document.querySelector(".side");
  menu?.addEventListener("click", () => {
    const open = menu.getAttribute("aria-expanded") !== "true";
    menu.setAttribute("aria-expanded", open); side.classList.toggle("open", open);
  });

  // Search: every word must occur; a hit in the title outranks one in the text.
  const q = document.getElementById("q"), results = document.getElementById("results");
  let index;
  const esc = s => s.replace(/[&<>"]/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
  const search = async () => {
    const words = q.value.toLowerCase().split(/\s+/).filter(w => w.length > 1);
    if (!words.length) { results.hidden = true; return; }
    index ??= await fetch("zoekindex.json").then(r => r.json()).catch(() => []);
    const hits = index.map(e => {
      const title = e.t.toLowerCase(), text = e.x.toLowerCase();
      if (!words.every(w => title.includes(w) || text.includes(w))) return null;
      return { e, score: words.reduce((s, w) => s + (title.includes(w) ? 10 : 1), 0) };
    }).filter(Boolean).sort((a, b) => b.score - a.score).slice(0, 8);
    results.innerHTML = hits.length
      ? hits.map(({ e }) => `<a href="${esc(e.u)}"><b>${esc(e.t)}</b><span>${esc(e.c)}</span></a>`).join("")
      : `<p>Niets gevonden voor "${esc(q.value)}". Probeer een ander woord, of bekijk het <a href="index.html">overzicht</a>.</p>`;
    results.hidden = false;
  };
  q?.addEventListener("input", search);
  q?.addEventListener("keydown", e => { if (e.key === "Escape") { q.value = ""; results.hidden = true; } });
  document.addEventListener("click", e => { if (!e.target.closest(".search")) results.hidden = true; });
  document.addEventListener("keydown", e => { if (e.key === "/" && !/INPUT|TEXTAREA/.test(document.activeElement.tagName)) { e.preventDefault(); q.focus(); } });

  document.querySelectorAll(".filter button").forEach(b => b.addEventListener("click", () => {
    document.querySelectorAll(".filter button").forEach(o => o.setAttribute("aria-pressed", o === b));
    document.querySelectorAll(".release").forEach(r => { r.hidden = !!b.dataset.tag && !r.dataset.tags.split("|").includes(b.dataset.tag); });
  }));
})();
