import { createMorph } from "./vendor/morphicons/dom.js";


const hoverIcons = {
  download: 'M12 3V15M7 10L12 15L17 10M5 16V21H19V16',
  external: 'M14 3H21V10M10 14L21 3M10 3H3V21H21V14',
  star: 'M12 3L14.5 9.5L21 12L14.5 14.5L12 21L9.5 14.5L3 12L9.5 9.5Z',
};
const motionPreference = matchMedia('(prefers-reduced-motion: reduce)');

document.querySelectorAll('[data-morph]').forEach(icon => {
  const link = icon.closest('a');
  const path = icon.querySelector('path');
  const resting = path.getAttribute('d');
  const active = hoverIcons[icon.dataset.morph];
  const morph = createMorph(path, resting, { reducedMotion: 'user' });
  let hovered = false;
  const target = () => hovered || link === document.activeElement ? active : resting;
  const update = () => morph.morphTo(target(), 'snappy');
  link.addEventListener('pointerenter', event => { if (event.pointerType !== 'touch') { hovered = true; update(); } });
  link.addEventListener('pointerleave', () => { hovered = false; update(); });
  link.addEventListener('focus', update);
  link.addEventListener('blur', update);
  motionPreference.addEventListener('change', () => { if (motionPreference.matches) morph.set(target()); });
});

const playPath = "M8 5 19 12 8 19Z";
const pausePath = "M8 5V19M16 5V19";
const playMorph = createMorph(document.querySelector("#play-icon path"), playPath, { reducedMotion: "user" });

document.querySelectorAll(".questions details").forEach(details => {
  const plus = "M5 12H19M12 5V19";
  const minus = "M5 12H19";
  const morph = createMorph(details.querySelector("summary path"), details.open ? minus : plus, { reducedMotion: "user" });
  details.addEventListener("toggle", () => morph.morphTo(details.open ? minus : plus, "snappy"));
});

(() => {
  const video = document.getElementById('preview');
  const slider = document.getElementById('lid');
  const button = document.getElementById('play');
  const label = document.getElementById('play-label');
  const reduced = matchMedia('(prefers-reduced-motion: reduce)');
  let scrubbing = false;
  function state(playing) {
    label.textContent = playing ? 'Pause' : 'Play the fold';
    playMorph.morphTo(playing ? pausePath : playPath, 'snappy');
    button.setAttribute('aria-label', playing ? 'Pause fold animation' : 'Play fold animation');
  }
  function updateSlider() {
    if (scrubbing || !Number.isFinite(video.duration)) return;
    const phase = video.currentTime / video.duration;
    slider.value = String(Math.round((phase <= .5 ? phase * 2 : (1 - phase) * 2) * 100));
    slider.setAttribute('aria-valuetext', `${slider.value}% closed`);
  }
  button.addEventListener('click', () => {
    if (!video.paused) { video.pause(); return; }
    if (video.ended || Number(slider.value) > 98) video.currentTime = 0;
    video.play().catch(() => state(false));
  });
  slider.addEventListener('input', () => {
    video.pause();
    if (!Number.isFinite(video.duration)) return;
    scrubbing = true;
    video.currentTime = Number(slider.value) / 100 * video.duration / 2;
    slider.setAttribute('aria-valuetext', `${slider.value}% closed`);
  });
  slider.addEventListener('change', () => { scrubbing = false; });
  video.addEventListener('play', () => state(true));
  video.addEventListener('pause', () => state(false));
  video.addEventListener('timeupdate', updateSlider);
  video.addEventListener('ended', () => { state(false); slider.value = '0'; slider.setAttribute('aria-valuetext', 'Lid open'); });
  video.addEventListener('error', () => { label.textContent = 'Preview unavailable'; button.disabled = true; slider.disabled = true; });
  document.addEventListener('visibilitychange', () => { if (document.hidden) video.pause(); });
  reduced.addEventListener('change', () => { if (reduced.matches) video.pause(); });
  // Play one short demonstration when it first comes into view, never a perpetual loop.
  const observer = new IntersectionObserver(entries => {
    if (entries.some(entry => entry.isIntersecting)) {
      if (!reduced.matches) video.play().catch(() => state(false));
      observer.disconnect();
    }
  }, { threshold: .3 });
  observer.observe(video);
})();
