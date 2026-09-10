import { createMorph } from "./vendor/morphicons/dom.js";

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
