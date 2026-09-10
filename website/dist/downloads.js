(async () => {
  const counter = document.getElementById('download-count');
  const cacheKey = 'bendmac-downloads';
  const cacheLifetime = 15 * 60 * 1000;

  function show(count) {
    counter.textContent = `${new Intl.NumberFormat('en').format(count)} downloads and counting`;
    counter.hidden = false;
  }

  try {
    const cached = JSON.parse(localStorage.getItem(cacheKey));
    const age = Date.now() - cached?.time;
    if (Number.isSafeInteger(cached?.count) && cached.count >= 0 && age >= 0 && age < cacheLifetime) {
      show(cached.count);
      return;
    }
  } catch {
    // The counter also works when browser storage is disabled.
  }

  try {
    let total = 0;
    for (let page = 1; ; page++) {
      const response = await fetch(`https://api.github.com/repos/IuCC123/BendMac/releases?per_page=100&page=${page}`, {
        headers: { Accept: 'application/vnd.github+json' },
        signal: AbortSignal.timeout(6000),
      });
      if (!response.ok) return;
      const releases = await response.json();
      if (!Array.isArray(releases)) return;
      for (const release of releases) {
        if (release.draft) continue;
        for (const asset of release.assets ?? []) {
          if (!/\.(dmg|zip)$/i.test(asset.name)) continue;
          if (!Number.isSafeInteger(asset.download_count) || asset.download_count < 0) return;
          total += asset.download_count;
        }
      }
      if (releases.length < 100) break;
    }
    if (!Number.isSafeInteger(total)) return;
    show(total);
    try {
      localStorage.setItem(cacheKey, JSON.stringify({ count: total, time: Date.now() }));
    } catch {
      // Caching is optional.
    }
  } catch {
    // Don't invent a count when GitHub is offline or rate-limits the request.
  }
})();
