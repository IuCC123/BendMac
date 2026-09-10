(() => {
  const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)');
  if (!('IntersectionObserver' in window) || !Element.prototype.animate) return;

  const animations = new Map();
  const sections = document.querySelectorAll(
    '.demo-section, .details-intro, .details-list > div, .open-inner, ' +
    '.getting-started h2, .questions details, .credit, .footer'
  );
  const observer = new IntersectionObserver(entries => {
    for (const entry of entries) {
      if (!entry.isIntersecting) continue;
      observer.unobserve(entry.target);
      if (reducedMotion.matches || entry.target.contains(document.activeElement)) continue;

      const animation = entry.target.animate([
        { opacity: 0, transform: 'translateY(18px)' },
        { opacity: 1, transform: 'translateY(0)' },
      ], {
        duration: 700,
        easing: 'cubic-bezier(0.22, 1, 0.36, 1)',
      });
      animations.set(entry.target, animation);
      animation.finished.then(() => animations.delete(entry.target)).catch(() => {});
    }
  }, { threshold: 0.08 });

  // Keep the initial viewport still. Content stays visible without JavaScript.
  for (const section of sections) {
    if (section.getBoundingClientRect().top >= window.innerHeight) observer.observe(section);
  }

  document.addEventListener('focusin', event => {
    for (const [element, animation] of animations) {
      if (element.contains(event.target)) animation.finish();
    }
  });
  reducedMotion.addEventListener('change', () => {
    if (!reducedMotion.matches) return;
    observer.disconnect();
    for (const animation of animations.values()) animation.cancel();
    animations.clear();
  });
})();
