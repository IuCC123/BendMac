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

document.addEventListener('previewstate', event => {
  playMorph.morphTo(event.detail.playing ? pausePath : playPath, 'snappy');
});
