(() => {
  const dialog = document.getElementById('compatibility-dialog');
  if (!dialog || typeof dialog.showModal !== 'function') return;
  // The researched chart is the single source for both the picker and reference.
  const models = [...dialog.querySelectorAll('.compat-table tbody')].flatMap(group => {
    const family = group.querySelector('.compat-family th').textContent;
    return [...group.querySelectorAll('tr')].slice(1).map(row => {
      const cells = row.children;
      return { family, model: cells[0].firstChild.textContent,
        chip: cells[0].querySelector('span').textContent, year: cells[1].textContent,
        status: cells[2].textContent };
    });
  });
  const title = dialog.querySelector('#compatibility-title');
  const intro = dialog.querySelector('#compatibility-intro');
  const stepLabel = dialog.querySelector('#compat-step');
  const select = dialog.querySelector('#compat-model');
  const next = dialog.querySelector('#compat-continue');
  const back = dialog.querySelector('#compat-back');
  const download = dialog.querySelector('#compatible-download');
  const reference = dialog.querySelector('.compat-reference');
  const panels = ['family', 'model', 'result'].map(name => dialog.querySelector(`#compat-${name}-step`));
  const markers = [...dialog.querySelectorAll('[data-wizard-step]')];
  const reduced = matchMedia('(prefers-reduced-motion: reduce)');
  let furthest = 0;
  let step = 0, family = '', choices = [];
  let panelAnimation;

  function updateRail() {
    markers.forEach((button, i) => {
      button.disabled = i > furthest;
      if (i === step) button.setAttribute('aria-current', 'step');
      else button.removeAttribute('aria-current');
      button.parentElement.classList.toggle('is-done', i < step);
      button.querySelector('.wizard-number').textContent = i < step ? '✓' : String(i + 1);
    });
  }

  function show(index) {
    const direction = index >= step ? 1 : -1;
    const changed = index !== step;
    step = index;
    furthest = Math.max(furthest, index);
    updateRail();
    panels.forEach((panel, i) => { panel.hidden = i !== index; });
    panelAnimation?.cancel();
    if (changed && !reduced.matches) {
      panelAnimation = panels[index].animate([
        { opacity: 0, transform: `translateX(${direction * 22}px)` },
        { opacity: 1, transform: 'translateX(0)' }
      ], { duration: 320, easing: 'cubic-bezier(.23,1,.32,1)' });
    }
    back.hidden = index === 0;
    stepLabel.textContent = ['Choose your Mac', 'Choose your model', 'Your compatibility'][index];
    reference.open = false;
    dialog.classList.remove('show-reference');
    dialog.scrollTop = 0;
    title.focus({ preventScroll: true });
  }
  function start() {
    title.textContent = 'Which MacBook is yours?';
    intro.textContent = '';
    show(0);
  }
  function chooseFamily(value) {
    furthest = 1;
    family = value;
    choices = models.filter(model => model.family === family);
    select.replaceChildren(new Option('Choose your model…', ''));
    choices.forEach((model, i) => {
      select.add(new Option(`${model.chip} · ${model.model} · ${model.year}`, String(i)));
    });
    next.disabled = true;
    showModels();
  }
  function showModels() {
    title.textContent = family === 'Other MacBooks' ? 'Which model?' : `Which ${family}?`;
    intro.textContent = '';
    show(1);
  }
  function result() {
    if (select.value === '') return;
    const model = choices[Number(select.value)];
    if (!model) return;
    intro.textContent = '';
    dialog.querySelector('#compat-selected').textContent = `${model.family === 'Other MacBooks' ? '' : model.family + ' · '}${model.model} · ${model.chip} · ${model.year}`;
    let badge, tone, copy, requirement = 'macOS 14+ · Apple silicon';
    download.hidden = false;
    download.textContent = 'Download for Mac';
    dialog.querySelector('#compat-source').hidden = true;
    if (model.status === 'Expected') {
      badge = 'Expected to work'; tone = 'caution';
      copy = 'Lid sensor confirmed. Not yet tested with BendMac.';
    } else if (model.status.startsWith('Tested')) {
      badge = 'Tested on M5 Air'; tone = 'success';
      copy = 'Both screen sizes have not been independently confirmed.';
    } else if (model.status === 'No lid tracking') {
      badge = 'No automatic folding'; tone = 'unsupported';
      copy = 'You can still use the manual preview.';
      download.textContent = 'Download for manual preview';
    } else if (model.status === 'Build unsupported') {
      badge = 'Not supported'; tone = 'unsupported';
      copy = 'This download requires Apple silicon.';
      requirement = '';
      download.hidden = true;
      dialog.querySelector('#compat-source').hidden = false;
    } else {
      badge = 'Not yet verified'; tone = 'caution';
      copy = 'Lid tracking and manual preview are unconfirmed.';
      requirement = 'Keep your Mac’s original macOS version or later.';
      download.textContent = 'Download to try';
    }
    title.textContent = 'Your compatibility.';
    const status = dialog.querySelector('#compat-result-status');
    status.className = `compat-result-status ${tone}`;
    status.textContent = `${tone === 'success' ? '✓' : tone === 'unsupported' ? '×' : '!'} ${badge}`;
    dialog.querySelector('#compat-result-copy').textContent = copy;
    dialog.querySelector('#compat-result-requirement').textContent = requirement;
    show(2);
  }
  dialog.querySelectorAll('[data-family]').forEach(button => button.addEventListener('click', () => chooseFamily(button.dataset.family)));
  select.addEventListener('change', () => { next.disabled = select.value === ''; furthest = 1; updateRail(); });
  next.addEventListener('click', result);
  back.addEventListener('click', () => { if (step === 2) showModels(); else start(); });
  function visit(index) {
    if (index > furthest || index === step) return;
    if (index === 0) start();
    else if (index === 1) showModels();
    else result();
    markers[index].focus();
  }
  markers.forEach((button, index) => {
    button.addEventListener('click', () => visit(index));
    button.addEventListener('keydown', event => {
      let to;
      if (event.key === 'ArrowRight') to = Math.min(furthest, index + 1);
      else if (event.key === 'ArrowLeft') to = Math.max(0, index - 1);
      else if (event.key === 'Home') to = 0;
      else if (event.key === 'End') to = furthest;
      else return;
      event.preventDefault();
      visit(to);
    });
  });
  reference.addEventListener('toggle', () => { dialog.classList.toggle('show-reference', reference.open); });
  const triggers = document.querySelectorAll('a[href$="/BendMac-macOS.dmg"]:not(#compatible-download), [data-compatibility]');
  triggers.forEach(trigger => {
    trigger.setAttribute('aria-haspopup', 'dialog');
    trigger.setAttribute('aria-controls', dialog.id);
    trigger.addEventListener('click', event => {
      if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
      event.preventDefault();
      furthest = 0;
      dialog.showModal();
      start();
    });
  });
  dialog.querySelector('.compatibility-close').addEventListener('click', () => dialog.close());
  dialog.addEventListener('click', event => {
    const box = dialog.getBoundingClientRect();
    if (event.target === dialog && (event.clientX < box.left || event.clientX > box.right || event.clientY < box.top || event.clientY > box.bottom)) dialog.close();
  });
  download.addEventListener('click', () => dialog.close());
})();
