/* Branches of characters flow outward as the open-source section passes through view. */
(() => {
  const section = document.getElementById('open-source');
  const canvas = document.getElementById('shared-art');
  const ctx = canvas.getContext('2d');
  if (!ctx) return;
  const reduced = matchMedia('(prefers-reduced-motion: reduce)');
  let width = 0, height = 0, progress = 0, target = 0;
  let frame = 0, last = 0, visible = false;
  const clamp = value => Math.max(0, Math.min(1, value));

  function paint() {
    ctx.clearRect(0, 0, width, height);
    const dark = document.documentElement.dataset.theme === 'dark';
    ctx.fillStyle = dark ? '#9baafa' : '#6063bb';
    ctx.font = '11px ui-monospace, SFMono-Regular, Menlo, Consolas, monospace';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    const spacing = width < 700 ? 17 : 20;
    // A faint bed of punctuation carries the artwork across the entire section.
    for (let y = 12; y < height; y += spacing) {
      for (let x = 10; x < width; x += spacing) {
        const center = Math.exp(-Math.pow((x - width / 2) / Math.min(width * .36, 340), 4));
        ctx.globalAlpha = .13 * (1 - center * .8);
        ctx.fillText('.', x, y);
      }
    }
    for (const side of [-1, 1]) {
      for (let branch = 0; branch < 9; branch++) {
        const spread = (branch - 4) / 4;
        const steps = Math.ceil(width * .7 / 8);
        for (let i = 0; i < steps; i++) {
          const t = i / steps;
          const travel = t * t * (3 - 2 * t);
          const x = width / 2 + side * (width * .58 - t * width * .75);
          const sway = Math.sin(t * 5 + progress * 2 + branch * .3) * 15 * t;
          const y = height * .5 + spread * height * .72 * travel + sway;
          if (y < 0 || y > height) continue;
          const center = Math.exp(-Math.pow((x - width / 2) / Math.min(width * .37, 355), 4));
          const edge = clamp(Math.min(y, height - y) / 45);
          const pulse = Math.pow(.5 + .5 * Math.cos(t * 12 - progress * 7 + branch * .8), 5);
          ctx.globalAlpha = (.24 + .42 * pulse) * (1 - center * .91) * edge;
          const chars = '.:+01';
          const index = Math.min(4, Math.floor(pulse * 5));
          ctx.fillText(i % 19 === 0 ? '+' : chars[index], x, y);
        }
      }
    }
    ctx.globalAlpha = 1;
  }

  function tick(now) {
    frame = 0;
    const delta = Math.min((now - last) / 1000, .05);
    last = now;
    progress += (target - progress) * (1 - Math.exp(-delta * 2));
    if (Math.abs(progress - target) < .0005) progress = target;
    paint();
    if (visible && !document.hidden && progress !== target) frame = requestAnimationFrame(tick);
  }
  function wake() {
    if (visible && !document.hidden && !frame) {
      last = performance.now();
      frame = requestAnimationFrame(tick);
    }
  }
  function update() {
    const rect = section.getBoundingClientRect();
    target = reduced.matches ? .3 : clamp((innerHeight - rect.top) / (innerHeight + rect.height));
    wake();
  }
  function resize() {
    width = section.clientWidth;
    height = section.clientHeight;
    const dpr = Math.min(devicePixelRatio || 1, 2);
    canvas.width = Math.round(width * dpr);
    canvas.height = Math.round(height * dpr);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    update();
    paint();
  }
  window.addEventListener('scroll', update, { passive: true });
  window.addEventListener('resize', resize, { passive: true });
  document.addEventListener('themechange', paint);
  reduced.addEventListener('change', () => {
    if (reduced.matches) progress = target = .3;
    update();
  });
  document.addEventListener('visibilitychange', () => {
    if (document.hidden) { cancelAnimationFrame(frame); frame = 0; }
    else update();
  });
  new ResizeObserver(resize).observe(section);
  new IntersectionObserver(entries => {
    visible = entries[0].isIntersecting;
    if (visible) update();
    else { cancelAnimationFrame(frame); frame = 0; }
  }).observe(section);
  resize();
})();
