// Apply the saved appearance before styles load, avoiding a flash on return visits.
(() => {
  const root = document.documentElement;
  const system = matchMedia('(prefers-color-scheme: dark)');
  const reduced = matchMedia('(prefers-reduced-motion: reduce)');
  let preference = null;
  try { preference = localStorage.getItem('bendmac-theme'); } catch {}
  if (preference !== 'light' && preference !== 'dark') preference = null;
  let button;
  let transition;

  function apply(theme) {
    root.dataset.theme = theme;
    const label = theme === 'dark' ? 'Switch to light mode' : 'Switch to dark mode';
    if (button) { button.setAttribute('aria-label', label); button.title = label; }
    document.querySelectorAll('meta[name="theme-color"]').forEach(meta => {
      meta.removeAttribute('media');
      meta.content = theme === 'dark' ? '#111113' : '#fafafa';
    });
    document.dispatchEvent(new Event('themechange'));
  }
  apply(preference || (system.matches ? 'dark' : 'light'));
  system.addEventListener('change', () => {
    if (!preference) apply(system.matches ? 'dark' : 'light');
  });

  document.addEventListener('DOMContentLoaded', () => {
    button = document.getElementById('theme-toggle');
    button.hidden = false;
    apply(root.dataset.theme);
    button.addEventListener('click', async () => {
      // Finish an in-flight fold before accepting the next one.
      if (transition) return;
      preference = root.dataset.theme === 'dark' ? 'light' : 'dark';
      try { localStorage.setItem('bendmac-theme', preference); } catch {}
      if (reduced.matches || !document.startViewTransition) {
        apply(preference);
        return;
      }
      transition = document.startViewTransition(() => apply(preference));
      try {
        await transition.ready;
        const fold = root.animate([
          { transform: 'rotateX(0deg)', filter: 'brightness(1) blur(0px)', opacity: 1 },
          { transform: 'rotateX(-35deg)', filter: 'brightness(.8) blur(1px)', opacity: .85, offset: .55 },
          { transform: 'rotateX(-90deg)', filter: 'brightness(.6) blur(5px)', opacity: 0 }
        ], { duration: 650, easing: 'cubic-bezier(.3,0,.2,1)', fill: 'forwards', pseudoElement: '::view-transition-old(root)' });
        await fold.finished;
        await transition.finished;
      } catch {
        transition.skipTransition();
      } finally { transition = null; }
    });
  });
})();
