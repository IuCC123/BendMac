/*
 * THESIS: A floating, folded sculpture made entirely of text, at hero scale.
 * OWN-WORLD: BendMac's neutral surface, with blue and violet typographic shading.
 * STORY: The sculpture bends softly, echoing the desktop's response to the lid.
 * FIRST VIEWPORT: A large open loop frames the centered headline and real Mac demo.
 * FORM: Reference-led ASCII material; the existing page composition is preserved.
 */
(() => {
  const stage = document.querySelector('.light-stage');
  const canvas = document.getElementById('ascii-art');
  const reduced = matchMedia('(prefers-reduced-motion: reduce)');
  const ctx = canvas.getContext('2d', { alpha: true });
  if (!ctx) return;

  const glyphs = '.:+147352698@';
  const samples = [];
  // A broad twisted band, sampled densely enough to rasterize into a text grid.
  for (let i = 0; i < 560; i++) {
    const u = i / 560 * Math.PI * 2;
    for (let j = 0; j < 90; j++) {
      const v = (j / 89 - .5) * .78;
      const twist = u * 1.5;
      const r = 1 + v * Math.cos(twist);
      const dr = -1.5 * v * Math.sin(twist);
      const x = r * Math.cos(u), y = r * Math.sin(u), z = v * Math.sin(twist);
      const ux = dr * Math.cos(u) - r * Math.sin(u);
      const uy = dr * Math.sin(u) + r * Math.cos(u);
      const uz = 1.5 * v * Math.cos(twist);
      const vx = Math.cos(twist) * Math.cos(u), vy = Math.cos(twist) * Math.sin(u);
      const vz = Math.sin(twist);
      const nx = uy * vz - uz * vy, ny = uz * vx - ux * vz, nz = ux * vy - uy * vx;
      const length = Math.hypot(nx, ny, nz);
      samples.push([x, y, z, nx / length, ny / length, nz / length, j / 89]);
    }
  }

  let width = 0, height = 0, columns = 0, rows = 0, cellX = 8, cellY = 11;
  let depth, light, material, quiet;
  let previous = 0, frame = 0, visible = true;
  let scrollTarget = 0, scrollTurn = 0;
  const clamp = (value, low, high) => Math.max(low, Math.min(high, value));
  const moving = () => !reduced.matches && visible && !document.hidden;

  function resize() {
    width = stage.clientWidth;
    height = stage.clientHeight;
    const ratio = Math.min(devicePixelRatio || 1, 2);
    canvas.width = Math.round(width * ratio);
    canvas.height = Math.round(height * ratio);
    ctx.setTransform(ratio, 0, 0, ratio, 0, 0);
    cellX = width < 700 ? 7 : 8;
    cellY = width < 700 ? 10 : 11;
    columns = Math.ceil(width / cellX);
    rows = Math.ceil(height / cellY);
    depth = new Float32Array(columns * rows);
    light = new Float32Array(depth.length);
    material = new Float32Array(depth.length);
    quiet = new Float32Array(depth.length);
    const bounds = stage.getBoundingClientRect();
    const protectedAreas = [...stage.querySelectorAll('.hero > *, .demo-caption')]
      .filter(element => element.getClientRects().length)
      .map(element => {
        // Follow the copy's bounds instead of the full-width paragraph box.
        const range = document.createRange();
        range.selectNodeContents(element);
        const rect = range.getBoundingClientRect();
        const half = rect.width / 2;
        return { x: rect.left - bounds.left + rect.width / 2, y: rect.top - bounds.top,
          half, bottom: rect.bottom - bounds.top };
      });
    for (let row = 0; row < rows; row++) {
      for (let col = 0; col < columns; col++) {
        const x = col * cellX, y = row * cellY;
        const edgeOpacity = Math.min(1, y / 70, (height - y) / 110);
        let textOpacity = 1;
        for (const area of protectedAreas) {
          const dx = Math.max(0, Math.abs(x - area.x) - area.half);
          const dy = Math.max(area.y - y, y - area.bottom, 0);
          const distance = Math.hypot(dx, dy);
          // Overlapping text areas share one veil instead of compounding it.
          textOpacity = Math.min(textOpacity, .32 + .68 * clamp(distance / 38, 0, 1));
        }
        quiet[row * columns + col] = edgeOpacity * textOpacity;
      }
    }
    updateScroll();
    wake();
  }

  function render() {
    ctx.clearRect(0, 0, width, height);
    depth.fill(-Infinity);
    const yaw = -.28 + scrollTurn * .08;
    const tilt = .58 + scrollTurn * .045;
    const roll = -.38;
    const cy = Math.cos(yaw), sy = Math.sin(yaw), ct = Math.cos(tilt), st = Math.sin(tilt);
    const cr = Math.cos(roll), sr = Math.sin(roll);
    const scaleX = Math.max(width * .47, 310);
    const scaleY = Math.min(height * .48, 540);
    for (const [x, y, z, nx, ny, nz, edge] of samples) {
      const ax = x * cy + z * sy, az = z * cy - x * sy;
      const by = y * ct - az * st, bz = y * st + az * ct;
      const px = ax * cr - by * sr, py = ax * sr + by * cr;
      const perspective = 1 / (1 - bz * .16);
      const col = Math.floor((width * .5 + px * scaleX * perspective) / cellX);
      const row = Math.floor((height * .45 + py * scaleY * perspective) / cellY);
      if (col < 0 || col >= columns || row < 0 || row >= rows) continue;
      const index = row * columns + col;
      if (bz <= depth[index]) continue;
      depth[index] = bz;
      const normalX = nx * cy + nz * sy, normalZ = nz * cy - nx * sy;
      const normalY = ny * ct - normalZ * st, normalDepth = ny * st + normalZ * ct;
      light[index] = clamp(Math.abs(normalX * -.35 + normalY * -.45 + normalDepth * .82), 0, 1);
      material[index] = edge;
    }
    ctx.font = `${width < 700 ? 9 : 10}px ui-monospace, SFMono-Regular, Menlo, Consolas, monospace`;
    ctx.textBaseline = 'top';
    const colors = document.documentElement.dataset.theme === 'dark' ? ['#8193f3', '#9faafa', '#b5bdfb'] : ['#435ac2', '#5754bd', '#7561c6'];
    for (let index = 0; index < depth.length; index++) {
      if (depth[index] === -Infinity || quiet[index] < .005) continue;
      const shade = light[index];
      const edgeFade = Math.min(1, material[index] * 12 + .2, (1 - material[index]) * 12 + .2);
      ctx.globalAlpha = (.16 + shade * .69) * quiet[index] * edgeFade;
      ctx.fillStyle = colors[Math.min(2, Math.floor(material[index] * 3))];
      const char = glyphs[Math.min(glyphs.length - 1, Math.floor(shade * (glyphs.length - 1)))];
      ctx.fillText(char, index % columns * cellX, Math.floor(index / columns) * cellY);
    }
    ctx.globalAlpha = 1;
  }

  function tick(now) {
    frame = 0;
    const delta = Math.min((now - previous) / 1000, .06);
    if (moving() && now - previous < 1000 / 24) { frame = requestAnimationFrame(tick); return; }
    previous = now;
    if (moving()) {
      // Ease over roughly a second, even after a fast trackpad swipe.
      const ease = 1 - Math.exp(-delta * .85);
      scrollTurn += (scrollTarget - scrollTurn) * ease;
    }
    render();
    if (moving() && Math.abs(scrollTarget - scrollTurn) > .0001) frame = requestAnimationFrame(tick);
  }
  function wake() {
    if (!frame && visible && !document.hidden) { previous = performance.now() - 50; frame = requestAnimationFrame(tick); }
  }
  function suspend() {
    cancelAnimationFrame(frame);
    frame = 0;
  }
  function updateScroll() {
    const rect = stage.getBoundingClientRect();
    scrollTarget = clamp(-rect.top / Math.max(rect.height, 1), 0, 1);
    if (moving()) wake();
  }
  window.addEventListener('scroll', updateScroll, { passive: true });
  function preference() {
    if (reduced.matches) scrollTurn = 0;
    suspend();
    wake();
  }
  reduced.addEventListener('change', preference);
  document.addEventListener('themechange', () => { if (depth) render(); });
  document.addEventListener('visibilitychange', () => { if (document.hidden) suspend(); else wake(); });
  new IntersectionObserver(entries => {
    visible = entries[0].isIntersecting;
    if (visible) wake(); else suspend();
  }).observe(stage);
  new ResizeObserver(resize).observe(stage);
  stage.classList.add('has-light');
  preference();
  resize();
})();
