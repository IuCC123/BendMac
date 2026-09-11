(() => {
  const video = document.getElementById('preview');
  const canvas = document.getElementById('scrub-preview');
  const context = canvas.getContext('2d');
  const reduced = matchMedia('(prefers-reduced-motion: reduce)');
  const frames = new Image();
  const laptop = document.querySelector('.macbook');
  const lid = laptop.querySelector('.lid-stage');
  let frame = 0, previous = 0, target = 0, progress = 0;
  let start = 0, distance = 1, lastSprite = -1;

  function paint() {
    const closure = Math.sin(progress * Math.PI / 2) ** 2;
    laptop.style.setProperty('--lid-angle', `${-68 * closure}deg`);
    laptop.style.setProperty('--lid-shade', String(closure * .25));
    if (!context || !frames.naturalWidth) return;
    const sprite = Math.round(progress * 63);
    if (sprite === lastSprite) return;
    context.drawImage(frames, (sprite % 8) * 480, Math.floor(sprite / 8) * 300,
      480, 300, 0, 0, 480, 300);
    lastSprite = sprite;
    canvas.hidden = false;
  }

  function tick(now) {
    frame = 0;
    const delta = Math.min((now - previous) / 1000, .05);
    previous = now;
    progress += (target - progress) * (1 - Math.exp(-delta * 5));
    if (Math.abs(target - progress) < .0005) progress = target;
    paint();
    if (progress !== target) frame = requestAnimationFrame(tick);
  }

  function update() {
    target = reduced.matches ? 0 : Math.max(0, Math.min(1, (window.scrollY - start) / distance));
    if (!frame && !document.hidden) {
      previous = performance.now();
      frame = requestAnimationFrame(tick);
    }
  }

  function resize() {
    laptop.style.perspective = `${laptop.clientWidth * 1.6}px`;
    laptop.style.perspectiveOrigin = `50% ${lid.offsetHeight}px`;
    // Start when the device enters the lower viewport; close as it approaches the top.
    const top = laptop.getBoundingClientRect().top + window.scrollY;
    start = Math.max(0, top - window.innerHeight * .7);
    distance = Math.max(window.innerHeight * .65, lid.offsetHeight);
    update();
  }

  frames.onload = paint;
  frames.src = 'assets/fold-frames.jpg?v=8';
  video.pause();
  window.addEventListener('scroll', update, { passive: true });
  window.addEventListener('resize', resize, { passive: true });
  window.addEventListener('pageshow', resize);
  new ResizeObserver(resize).observe(document.querySelector('.light-stage'));
  reduced.addEventListener('change', () => {
    if (reduced.matches) {
      cancelAnimationFrame(frame);
      frame = 0;
      progress = target = 0;
      paint();
    } else update();
  });
  document.addEventListener('visibilitychange', () => {
    if (document.hidden) { cancelAnimationFrame(frame); frame = 0; }
    else update();
  });
  resize();
})();
