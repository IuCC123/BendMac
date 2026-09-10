(() => {
  const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)');
  if (reducedMotion.matches || !('IntersectionObserver' in window)) return;

  const pending = new Set();
  const sections = document.querySelectorAll(
    '.demo-section, .details-intro, .details-list > div, .open-inner, ' +
    '.getting-started h2, .questions details, .credit, .footer'
  );

  function reveal(element) {
    element.classList.remove('reveal-pending');
    pending.delete(element);
    observer.unobserve(element);
  }

  const observer = new IntersectionObserver(entries => {
    for (const entry of entries) {
      if (entry.isIntersecting) reveal(entry.target);
    }
  }, { rootMargin: '0px 0px 48px 0px', threshold: 0 });

  // Set the starting state while elements are still below the viewport.
  // The observer then reveals them before they cross its lower edge.
  for (const section of sections) {
    if (section.getBoundingClientRect().top < window.innerHeight + 48) continue;
    section.classList.add('scroll-reveal', 'reveal-pending');
    pending.add(section);
    observer.observe(section);
  }

  document.addEventListener('focusin', event => {
    for (const section of pending) {
      if (section.contains(event.target)) reveal(section);
    }
  });
  reducedMotion.addEventListener('change', () => {
    if (!reducedMotion.matches) return;
    for (const section of pending) reveal(section);
    observer.disconnect();
  });
})();
