(() => {
  const header = document.querySelector('.nav');
  let pending = false;
  function update() {
    pending = false;
    // A small dead zone keeps the glass from flickering at the scroll boundary.
    const floating = header.classList.contains('is-floating');
    header.classList.toggle('is-floating', window.scrollY > (floating ? 12 : 44));
  }
  window.addEventListener('scroll', () => {
    if (!pending) { pending = true; requestAnimationFrame(update); }
  }, { passive: true });
  window.addEventListener('pageshow', update);
  update();
})();
