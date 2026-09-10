const link = document.getElementById('github-stars');
const counter = document.getElementById('star-count');
const cacheKey = 'bendmac-github-stars';
const cacheLifetime = 5 * 60 * 1000;

function showCount(count) {
  counter.textContent = new Intl.NumberFormat('en').format(count);
  counter.hidden = false;
  link.setAttribute('aria-label', `Star BendMac on GitHub (${count} stars)`);
}

function readCache() {
  try {
    const cached = JSON.parse(localStorage.getItem(cacheKey));
    if (Number.isSafeInteger(cached?.count) && cached.count >= 0 && Number.isFinite(cached?.time)) {
      return cached;
    }
  } catch {
    // Storage may be disabled; the public API still works without it.
  }
  return null;
}

async function updateStars() {
  const cached = readCache();
  const age = cached ? Date.now() - cached.time : Infinity;
  if (age >= 0 && age < cacheLifetime) {
    showCount(cached.count);
    return;
  }

  try {
    const response = await fetch('https://api.github.com/repos/IuCC123/BendMac', {
      headers: { Accept: 'application/vnd.github+json' },
      signal: AbortSignal.timeout(6000),
    });
    if (!response.ok) return;
    const { stargazers_count: count } = await response.json();
    if (!Number.isSafeInteger(count) || count < 0) return;
    showCount(count);
    try {
      localStorage.setItem(cacheKey, JSON.stringify({ count, time: Date.now() }));
    } catch {
      // A blocked cache should not hide a successfully fetched count.
    }
  } catch {
    // Keep the Star link usable if GitHub is unavailable or rate-limits requests.
  }
}

updateStars();
