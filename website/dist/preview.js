(() => {
  const video = document.getElementById('preview');
  const canvas = document.getElementById('scrub-preview');
  const context = canvas.getContext('2d');
  const slider = document.getElementById('lid');
  const button = document.getElementById('play');
  const label = document.getElementById('play-label');
  const reduced = matchMedia('(prefers-reduced-motion: reduce)');
  const frames = new Image();
  let manual = false;
  let interacted = false;
  let pendingPlay = false;
  function state() {
    const playing = !video.paused;
    label.textContent = playing ? 'Pause' : 'Play the fold';
    button.setAttribute('aria-label', playing ? 'Pause fold animation' : 'Play fold animation');
    document.dispatchEvent(new CustomEvent('previewstate', { detail: { playing } }));
  }
  function draw() {
    if (!frames.complete || !frames.naturalWidth) return;
    const frame = Math.round(Number(slider.value) / 100 * 63);
    context.drawImage(frames, (frame % 8) * 480, Math.floor(frame / 8) * 300,
      480, 300, 0, 0, 480, 300);
    canvas.hidden = false;
  }
  frames.onload = () => { if (manual) draw(); };
  frames.src = 'assets/fold-frames.jpg?v=5';
  slider.addEventListener('input', () => {
    interacted = true;
    pendingPlay = false;
    manual = true;
    video.pause();
    slider.setAttribute('aria-valuetext', `${slider.value}% closed`);
    draw();
  });
  function play() {
    if (!Number.isFinite(video.duration)) { pendingPlay = true; video.load(); return; }
    if (manual) video.currentTime = Number(slider.value) / 100 * 2.1;
    else if (video.ended) video.currentTime = 0;
    manual = false;
    video.play().then(() => { canvas.hidden = true; }).catch(state);
  }
  button.addEventListener('click', () => {
    interacted = true;
    if (!video.paused) video.pause(); else play();
  });
  video.addEventListener('loadedmetadata', () => {
    if (pendingPlay) { pendingPlay = false; play(); }
  });
  video.addEventListener('play', state);
  video.addEventListener('pause', state);
  video.addEventListener('timeupdate', () => {
    if (manual) return;
    const phase = Math.min(1, video.currentTime / 4.2);
    slider.value = String(Math.round((phase <= .5 ? phase * 2 : (1 - phase) * 2) * 100));
    slider.setAttribute('aria-valuetext', `${slider.value}% closed`);
  });
  video.addEventListener('error', () => { label.textContent = 'Playback unavailable'; button.disabled = true; });
  document.addEventListener('visibilitychange', () => { if (document.hidden) video.pause(); });
  reduced.addEventListener('change', () => { if (reduced.matches) video.pause(); });
  const observer = new IntersectionObserver(entries => {
    if (entries.some(entry => entry.isIntersecting)) {
      if (!reduced.matches && !interacted) play();
      observer.disconnect();
    }
  }, { threshold: .3 });
  observer.observe(video);
})();
