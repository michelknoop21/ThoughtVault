(async () => {
  const status = document.querySelector('#status');
  const host = document.querySelector('#downloads');
  try {
    const response = await fetch('releases.json', {cache:'no-store', referrerPolicy:'no-referrer'});
    if (!response.ok) throw new Error('manifest');
    const releases = await response.json();
    const platforms = [['macos','macOS'],['windows_x64','Windows x64'],['windows_arm64','Windows ARM64']];
    for (const [key, label] of platforms) {
      const entry = releases[key] ?? (key === 'windows_x64' ? releases.windows : null);
      if (!entry || !/^[A-Za-z0-9._-]+\.(dmg|msi)$/.test(entry.filename)) continue;
      const link = document.createElement('a');
      link.className = 'download-row';
      link.href = new URL(encodeURIComponent(entry.filename), location.href).href;
      link.rel = 'nofollow noreferrer';
      link.download = entry.filename;
      const title = document.createElement('strong');
      title.textContent = `${label} · versie ${entry.version}`;
      link.append(title);
      host.append(link);
    }
    status.textContent = host.children.length ? 'Download de nieuwste beschikbare versie per platform.' : 'Er zijn nog geen installers beschikbaar.';
  } catch {
    status.textContent = 'De downloads konden niet worden geladen. Probeer het opnieuw of neem contact op.';
  }
})();
