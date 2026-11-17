(async () => {
  const status = document.querySelector('#status');
  const host = document.querySelector('#downloads');
  const retry = document.querySelector('#retry');
  const note = document.querySelector('#device-note');
  const agent = navigator.userAgent;
  const mobile = /Android|iPhone|iPad|iPod/i.test(agent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  const os = mobile ? null : /Mac/i.test(navigator.userAgentData?.platform || navigator.platform) ? 'macos' : /Win/i.test(navigator.userAgentData?.platform || navigator.platform) ? 'windows' : null;
  let windowsArch = null;
  if (os === 'windows') {
    try {
      const data = await navigator.userAgentData?.getHighEntropyValues(['architecture', 'bitness']);
      if (data?.architecture === 'arm' && data.bitness === '64') windowsArch = 'windows_arm64';
      if (data?.architecture === 'x86' && data.bitness === '64') windowsArch = 'windows_x64';
    } catch { /* Browser privacy settings can withhold architecture. */ }
  }
  const recommended = os === 'macos' ? 'macos' : windowsArch;
  note.textContent = os === 'macos' ? 'Je gebruikt een Mac. De macOS-download staat vooraan.' : os === 'windows' ? windowsArch ? 'De aanbevolen Windows-versie staat vooraan.' : 'Je gebruikt Windows. Kies de processor van jouw computer.' : 'Kies de versie voor de computer waarop je ThoughtVault gaat gebruiken.';
  const platforms = [['macos','macOS','Voor je Mac'],['windows_x64','Windows x64','Voor Intel- en AMD-processors'],['windows_arm64','Windows ARM64','Voor ARM-processors, zoals Snapdragon']];
  const priority = key => key === recommended ? 2 : os === 'windows' && key.startsWith('windows') ? 1 : 0;
  const icon = '<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="3" y="4" width="18" height="13" rx="2"/><path d="M8 21h8M12 17v4"/></svg>';
  async function load() {
    retry.hidden = true;
    host.setAttribute('aria-busy', 'true');
    status.textContent = 'Beschikbare versies laden…';
    try {
      const response = await fetch('releases.json', {cache:'no-store', referrerPolicy:'no-referrer'});
      if (!response.ok) throw new Error('manifest');
      const releases = await response.json();
      const cards = [];
      for (const [key, label, hint] of [...platforms].sort((a,b) => priority(b[0]) - priority(a[0]))) {
        const entry = releases[key] ?? (key === 'windows_x64' ? releases.windows : null);
        if (!entry || !/^[A-Za-z0-9._-]+\.(dmg|msi)$/.test(entry.filename)) continue;
        const card = document.createElement('article');
        const preferred = key === recommended || (os === 'windows' && !windowsArch && key.startsWith('windows'));
        card.className = `download-card${preferred ? ' recommended' : ''}`;
        card.innerHTML = `${preferred ? `<span class="recommendation">${key === recommended ? 'Aanbevolen voor jou' : 'Voor jouw besturingssysteem'}</span>` : ''}<div class="card-top"><span class="platform-icon">${icon}</span><div><h3></h3><p class="version"></p></div></div><a class="button" rel="nofollow noreferrer"><span></span><span class="end" aria-hidden="true"><svg viewBox="0 0 24 24"><path d="M12 3v12m-5-5 5 5 5-5M5 16v4h14v-4"/></svg></span></a><p class="platform-hint"></p>`;
        card.querySelector('h3').textContent = label;
        card.querySelector('.version').textContent = `Versie ${entry.version} · ${entry.filename.endsWith('.dmg') ? 'DMG' : 'MSI'}`;
        card.querySelector('.platform-hint').textContent = hint;
        const link = card.querySelector('a');
        link.href = new URL(encodeURIComponent(entry.filename), location.href).href;
        link.download = entry.filename;
        link.querySelector('span').textContent = `Download voor ${label}`;
        cards.push(card);
      }
      host.replaceChildren(...cards);
      status.textContent = cards.length ? 'De nieuwste beschikbare versie per platform.' : 'Er zijn nog geen installers beschikbaar. Probeer het later opnieuw of stel ons een vraag.';
    } catch {
      host.replaceChildren();
      status.textContent = 'De downloads konden niet worden geladen. Controleer je verbinding en probeer opnieuw.';
      retry.hidden = false;
    } finally { host.setAttribute('aria-busy', 'false'); }
  }
  retry.addEventListener('click', load);
  await load();
})();
