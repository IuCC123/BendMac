/* The letters settle onto their baseline as you scroll into the footer. */
(() => {
  const section = document.querySelector('.footer-art');
  const letters = [...section.querySelectorAll('.footer-type span')];
  const reduced = matchMedia('(prefers-reduced-motion: reduce)');
  let visible = false, frame = 0, last = 0, value = 0, target = 0;
  function paint() {
    letters.forEach((letter, i) => {
      const phase = Math.max(0, Math.min(1, (value - i * .055) / .65));
      const bend = reduced.matches ? 0 : Math.sin(phase * Math.PI) * (1 - phase * .3);
      letter.style.transform = `translateY(${-bend * 22}%) rotateX(${bend * -32}deg)`;
    });
  }
  function tick(now) {
    frame = 0;
    const delta = Math.min((now - last) / 1000, .05);
    last = now;
    value += (target - value) * (1 - Math.exp(-delta * 4));
    if (Math.abs(value - target) < .0001) value = target;
    paint();
    if (visible && !document.hidden && value !== target) frame = requestAnimationFrame(tick);
  }
  function update() {
    const rect = section.getBoundingClientRect();
    target = reduced.matches ? 1 : Math.max(0, Math.min(1, (innerHeight - rect.top) / Math.max(rect.height, 1)));
    if (!frame && visible && !document.hidden) { last = performance.now(); frame = requestAnimationFrame(tick); }
  }
  window.addEventListener('scroll', update, { passive: true });
  window.addEventListener('resize', update, { passive: true });
  reduced.addEventListener('change', () => { paint(); update(); });
  document.addEventListener('visibilitychange', () => {
    if (document.hidden) { cancelAnimationFrame(frame); frame = 0; } else update();
  });
  new IntersectionObserver(entries => {
    visible = entries[0].isIntersecting;
    if (visible) update(); else { cancelAnimationFrame(frame); frame = 0; }
  }).observe(section);
})();
