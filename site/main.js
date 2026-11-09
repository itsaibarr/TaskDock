// TaskDock site: picker demo, agent showcase, Dock toggle, Works-with card.

// Keyboard-initiated changes never animate (emilkowalski/skills); pointer-initiated ones may.
let byKeyboard = false;
addEventListener('keydown', () => (byKeyboard = true), true);
addEventListener('pointerdown', () => (byKeyboard = false), true);
const animated = () => !byKeyboard; // reduced motion keeps fades; CSS removes the movement

// ---------- Picker demo (mirrors Sources/TaskDock/Picker.swift; strings verbatim) ----------
const TEMPLATES = () => [
  { id: 'w', emoji: '✍️', name: 'Writing', note: 'page 45, exercise 4.3 done; next: try 4.4 before reading 4.5',
    resume: { ago: '2 hours ago', chips: [['3 tabs', 'helium'], ['Calculus Early Transcendentals', 'preview'], ['Week 3 notes', 'obsidian']] } },
  { id: 'c', emoji: '💻', name: 'Coding', note: '' },
  { id: 's', emoji: '📚', name: 'Study IELTS', note: '' },
];
const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const rv = (reveal) => (reveal && animated() ? 'reveal-in' : '');
const icon = (id, cls = '') => `<svg class="${cls}" aria-hidden="true"><use href="#i-${id}"/></svg>`;

function Picker(root, { nudge = null, status } = {}) {
  const s = { view: 'list', expanded: true, query: '', index: 0, chosen: null, goal: '', fresh: false,
              templates: TEMPLATES(), session: null, note: '' };
  const say = (msg) => { if (status) status.textContent = msg; };
  const suggestion = () => (s.query === '' && !nudge ? { title: 'Writing chapter 3', template: 'w', time: '10:00–11:00' } : null);
  const lead = () => (suggestion() ? 1 : 0);
  const matches = () => s.templates.filter((t) => t.id !== nudge && (s.query === '' || t.name.toLowerCase().includes(s.query.toLowerCase()) || t.emoji === s.query));
  const tpl = (id) => s.templates.find((t) => t.id === id);

  function render({ reveal = false, focus = true, caret = null } = {}) {
    root.dataset.open = String(s.view === 'list' ? s.expanded : s.view !== 'closed');
    if (s.view === 'closed') root.innerHTML = closedView();
    else if (s.view === 'finish') root.innerHTML = finishView(reveal);
    else if (s.view === 'goal') root.innerHTML = goalView(reveal);
    else root.innerHTML = listView(reveal);
    bind();
    if (!focus) return;
    const inp = root.querySelector('input');
    if (inp) { inp.focus({ preventScroll: true }); const c = caret ?? inp.value.length; inp.setSelectionRange(c, c); }
    else root.querySelector('[data-act=open]')?.focus({ preventScroll: true }); // closed: focus the reopen key
  }

  function listView(reveal) {
    const m = matches(), sug = suggestion();
    const row = (i, chip, title, note, attrs) => `<div class="p-row" role="option" id="${root.id}-o${i}" aria-selected="${i === s.index}" data-i="${i}" ${attrs || ''}>${chip}<span class="t">${esc(title)}</span>${note ? `<span class="n">${esc(note)}</span>` : ''}</div>`;
    let rows = '';
    if (sug) rows += `<div class="p-label">${icon('cal')}Suggested from Calendar</div><div class="p-list" role="presentation">${row(0, `<span class="chip">${tpl(sug.template).emoji}</span>`, sug.title, `${tpl(sug.template).name} · ${sug.time}`)}</div><div class="p-label">${icon('stack')}Templates</div>`;
    rows += `<div class="p-list ${sug ? '' : 'solo'}" role="presentation">` + m.map((t, i) => row(i + lead(), `<span class="chip">${t.emoji}</span>`, t.name, t.note)).join('')
      + row(m.length + lead(), `<span class="chip">${icon('plus')}</span>`, s.query ? `New Template “${s.query}”` : 'New Template', '') + '</div>';
    const head = nudge ? `<div class="p-nudge">${icon('sparkles')}<span>Agent is on it</span><span class="m">· ${tpl(nudge).emoji} ${esc(tpl(nudge).name)}</span></div>` : '';
    const ph = nudge ? 'What will you do meanwhile?' : 'Start a task…';
    return `${head}<div class="p-card p-search">${icon('scope', 'p-scope')}<input class="p-input" type="text" role="combobox" aria-expanded="${s.expanded}" aria-controls="${root.id}-lb" aria-activedescendant="${s.expanded ? `${root.id}-o${s.index}` : ''}" aria-label="${ph}" autocomplete="off" spellcheck="false" placeholder="${ph}" value="${esc(s.query)}"></div>`
      + (s.expanded ? `<div id="${root.id}-lb" role="listbox" aria-label="Templates" class="${rv(reveal)}">${rows}<div class="p-foot p-hint">↑↓ choose · ↩ select · esc close</div></div>` : '');
  }

  function goalView(reveal) {
    const t = tpl(s.chosen), r = t.resume;
    const resume = (r || t.note) ? `<div class="p-resume" data-fresh="${s.fresh}"><div class="top">${icon('back')}<span>${s.fresh ? 'Starting fresh' : 'Pick up where you left off'}</span>${r ? `<span>· ${r.ago}</span><button type="button" data-act="fresh">${s.fresh ? 'Resume' : 'Start fresh'}</button>` : ''}</div>${t.note ? `<div class="note">${esc(t.note)}</div>` : ''}${r ? `<div class="p-chips">${r.chips.map(([c, app]) => `<span>${app ? `<img src="assets/icons/${app}.webp" width="14" height="14" alt="">` : ''}${esc(c)}</span>`).join('')}</div>` : ''}</div>` : '';
    return `<div class="${rv(reveal)}"><div class="p-head"><span class="chip big">${t.emoji}</span><span class="name">${esc(t.name)}</span></div>
      <div class="p-card p-compose">${resume}<input class="p-input" type="text" aria-label="What will you finish? (optional)" placeholder="What will you finish? (optional)" value="${esc(s.goal)}" autocomplete="off">
      <div class="p-row2"><span class="p-hint">${r && !s.fresh ? '↩ resume · esc close' : '↩ start · esc close'}</span><button class="p-send" type="button" data-act="start" aria-label="Start">${icon('up')}</button></div></div></div>`;
  }

  function finishView(reveal) {
    const ss = s.session, t = tpl(ss.id), mins = Math.floor((Date.now() - ss.at) / 60000);
    return `<div class="${rv(reveal)}"><div class="p-head"><span class="chip">${t.emoji}</span><span class="sm">${esc(t.name)} · ${mins}m</span></div>
      <div class="p-card p-compose">${ss.goal !== t.name ? `<div class="p-goal">${esc(ss.goal)}</div>` : ''}<input class="p-input" type="text" aria-label="Where did you stop? What's next?" placeholder="Where did you stop? What's next?" value="${esc(s.note)}" autocomplete="off">
      <div class="p-row2"><span class="p-hint">Open tabs and files are saved · esc close</span><button class="p-pill" type="button" data-act="switch">Switch Task…</button><button class="p-pill p-pill--blue" type="button" data-act="finish">Finish</button></div></div></div>`;
  }

  function closedView() {
    const ss = s.session, t = ss && tpl(ss.id);
    return `<div class="p-closed"><span>${ss ? `Running: ${t.emoji} ${esc(ss.goal)}` : 'Picker closed'}</span><button class="keycap glass" type="button" data-act="open"><kbd>⌃⌥Space</kbd></button></div>`;
  }

  function bind() {
    const input = root.querySelector('input');
    root.querySelectorAll('[data-i]').forEach((el) => {
      el.addEventListener('pointerenter', () => { if (s.index !== +el.dataset.i) { s.index = +el.dataset.i; mark(); } });
      el.addEventListener('click', () => { s.index = +el.dataset.i; pick(); });
    });
    root.querySelectorAll('[data-act]').forEach((b) => b.addEventListener('click', () => act(b.dataset.act)));
    root.querySelector('.p-search')?.addEventListener('click', () => expand());
    if (!input) return;
    input.addEventListener('compositionend', () => input.dispatchEvent(new Event('input')));
    input.addEventListener('input', (e) => {
      if (e.isComposing) return; // let IME and dead-key input finish before re-rendering
      if (s.view === 'list') { s.query = input.value; s.index = 0; const was = s.expanded; s.expanded = true; render({ reveal: !was, caret: input.selectionStart }); }
      else if (s.view === 'goal') s.goal = input.value; else s.note = input.value;
    });
    input.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') { e.preventDefault(); close(); }
      else if (e.key === 'Enter') { e.preventDefault(); s.view === 'list' ? (s.expanded ? pick() : expand()) : s.view === 'goal' ? start() : finish(); }
      else if (s.view === 'list' && (e.key === 'ArrowDown' || e.key === 'ArrowUp')) {
        e.preventDefault();
        if (!s.expanded) return expand();
        s.index = Math.min(Math.max(s.index + (e.key === 'ArrowDown' ? 1 : -1), 0), matches().length + lead()); mark(); // instant: keyboard-driven
      }
    });
  }
  function mark() {
    root.querySelectorAll('[data-i]').forEach((el) => el.setAttribute('aria-selected', String(+el.dataset.i === s.index)));
    root.querySelector('input')?.setAttribute('aria-activedescendant', `${root.id}-o${s.index}`);
  }
  function expand() {
    if (s.expanded) return;
    s.expanded = true; root.classList.remove('morph');
    if (animated()) { void root.offsetWidth; root.classList.add('morph'); }
    render({ reveal: true });
  }
  function pick() {
    const sug = suggestion(), m = matches();
    if (sug && s.index === 0) { s.goal = sug.title; return choose(sug.template); }
    const t = m[s.index - lead()];
    s.goal = '';
    if (t) return choose(t.id);
    const name = s.query || 'New task';
    s.templates.push({ id: 'n' + s.templates.length, emoji: '⭐', name, note: '' });
    say(`Created template ${name}. In the app, its app list opens next.`);
    choose(s.templates.at(-1).id);
  }
  function choose(id) { s.chosen = id; s.fresh = false; s.view = 'goal'; render({ reveal: true }); say(`${tpl(id).name} chosen.`); }
  function start() {
    const t = tpl(s.chosen), g = s.goal.trim();
    s.session = { id: t.id, goal: g || t.name, at: Date.now() };
    s.view = 'closed'; s.query = ''; s.goal = ''; s.index = 0;
    render();
    say(`Started ${t.name}${t.resume && !s.fresh ? ', reopening what was saved' : ''}. Only its apps stay in the Dock.`);
  }
  function finish() {
    const t = tpl(s.session.id); t.note = s.note.trim() || t.note;
    s.session = null; s.note = ''; s.view = 'closed';
    render();
    say('Finished. Your apps and Dock are back the way they were.');
  }
  function close() {
    if (s.view === 'goal') { s.view = 'list'; s.chosen = null; s.goal = ''; return render(); } // back to the list, like dismissing the start card
    s.view = 'closed'; render(); say('Picker closed.');
  }
  function act(a) {
    if (a === 'open') { s.view = s.session ? 'finish' : 'list'; s.expanded = !!s.session || !!nudge; s.query = ''; s.index = 0; render({ reveal: true }); say(s.session ? 'Finish card open.' : 'Picker open.'); }
    else if (a === 'fresh') { s.fresh = !s.fresh; render(); }
    else if (a === 'start') start();
    else if (a === 'finish') finish();
    else if (a === 'switch') { s.view = 'list'; s.expanded = true; render({ reveal: true }); }
  }
  render({ focus: false });
}

Picker(document.getElementById('picker-demo'), { status: document.getElementById('picker-demo-status') });
Picker(document.getElementById('nudge-demo'), { nudge: 'c', status: document.getElementById('picker-demo-status') });

// ---------- Agent showcase ----------
const MENU = ['💻 Fix the login redirect · 12m ⧗', '💻 Fix the login redirect · 14m ⧗', '✍️ Draft the intro section · 1m ⧗', '✍️ Draft the intro section · 21m ✓', '💻 Fix the login redirect · 35m'];
const stepButtons = [...document.querySelectorAll('.step button')];
const screen = document.getElementById('screen');
const views = [...document.querySelectorAll('.view')], mbLabel = document.getElementById('mb-label');
function showStep(n) {
  screen.classList.toggle('instant', !animated());
  stepButtons.forEach((b, i) => { b.setAttribute('aria-pressed', String(i === n)); b.parentElement.dataset.active = String(i === n); });
  views.forEach((v) => (v.hidden = +v.dataset.view !== n));
  mbLabel.textContent = MENU[n];
}
stepButtons.forEach((b, i) => {
  b.addEventListener('click', () => showStep(i));
  b.addEventListener('keydown', (e) => {
    const d = { ArrowDown: 1, ArrowUp: -1 }[e.key];
    if (!d) return;
    e.preventDefault(); const j = (i + d + stepButtons.length) % stepButtons.length; stepButtons[j].focus(); showStep(j);
  });
});

// ---------- Dock toggle: icons move to their new place (View Transitions), or swap instantly ----------
const dock = document.querySelector('.dock');
const CAPTIONS = {
  before: 'Before: your usual Dock, with everything you pinned and everything running.',
  task: "During the task, the Dock shows the template's apps. Mail and Messages are hidden, not quit, and keep their icon because macOS shows every running app.",
};
document.querySelectorAll('[data-dock]').forEach((b) => b.addEventListener('click', () => {
  if (dock.dataset.state === b.dataset.dock) return;
  const swap = () => {
    dock.dataset.state = b.dataset.dock;
    document.querySelectorAll('[data-dock]').forEach((x) => x.setAttribute('aria-pressed', String(x === b)));
    document.getElementById('dock-caption').textContent = CAPTIONS[b.dataset.dock];
  };
  document.startViewTransition && animated() ? document.startViewTransition(swap) : swap();
}));

// ---------- Works-with: the active row's real icon fills the card ----------
const idx = [...document.querySelectorAll('.index a')];
const [indexK, indexLine, indexIcon] = ['index-k', 'index-line', 'index-icon'].map((id) => document.getElementById(id));
const setIdx = (a) => {
  if (a.hasAttribute('aria-current')) return;
  idx.forEach((x) => x.removeAttribute('aria-current'));
  a.setAttribute('aria-current', 'true');
  indexK.textContent = a.querySelector('.name').textContent;
  indexLine.textContent = a.nextElementSibling.textContent;
  indexIcon.src = a.querySelector('.row-icon').src;
};
idx.forEach((a) => { a.addEventListener('pointerenter', () => setIdx(a)); a.addEventListener('focus', () => setIdx(a)); });
if (idx[0]) setIdx(idx[0]);
