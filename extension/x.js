// Runs on x.com: adds a ◎ "Save to TaskDock" button to every post's action row. One click saves the post's
// link and exact text; a small field then lets you add a thought (↩ saves it, Esc or 5 s idle closes it).
// The background script queues saves until the TaskDock app confirms them.
(() => {
  const saved = new Set();
  const ICON = '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="8" fill="none" stroke="currentColor" stroke-width="1.8"/><circle cx="12" cy="12" r="2.6" fill="currentColor"/></svg>';
  const CHECK = '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="8" fill="none" stroke="currentColor" stroke-width="1.8"/><path d="M8.4 12.3l2.4 2.4 4.8-5" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>';

  // Text as shown, with emoji (images on X) and line breaks kept.
  const textOf = (el) => [...el.childNodes].map((n) =>
    n.nodeType === Node.TEXT_NODE ? n.data : n.nodeName === 'IMG' ? n.alt : n.nodeName === 'BR' ? '\n' : textOf(n)).join('');

  function postOf(article) {
    const link = article.querySelector('a[href*="/status/"] time')?.closest('a');
    const m = link?.getAttribute('href')?.match(/^\/(\w+)\/status\/(\d+)/);
    if (!m) return null;
    // A quoted post sits inside a role=link card; its text isn't this post's.
    const body = [...article.querySelectorAll('[data-testid="tweetText"]')].find((e) => !e.closest('div[role="link"]'));
    const name = article.querySelector('[data-testid="User-Name"] a span');
    return {
      id: m[2], handle: m[1], url: `https://x.com/${m[1]}/status/${m[2]}`,
      author: (name && textOf(name).trim()) || m[1],
      text: body ? textOf(body).trim() : '',
      postedAt: link.querySelector('time')?.getAttribute('datetime') ?? undefined,
      partial: !!article.querySelector('[data-testid="tweet-text-show-more-link"]'),
    };
  }

  function send(post) {
    try {
      chrome.runtime.sendMessage({ type: 'save-post', post });
      return true;
    } catch { // the extension was reloaded; this page still runs the old script
      return false;
    }
  }

  function paint(btn) {
    const on = saved.has(btn.dataset.id);
    btn.classList.toggle('is-saved', on);
    btn.innerHTML = on ? CHECK : ICON;
    btn.setAttribute('aria-label', on ? 'Saved in TaskDock. Add a thought' : 'Save to TaskDock');
    btn.title = on ? 'Saved in TaskDock. Click to add a thought' : 'Save to TaskDock';
  }

  function scan() {
    for (const article of document.querySelectorAll('article[data-testid="tweet"]')) {
      const group = article.querySelector('[data-testid="reply"]')?.closest('[role="group"]');
      const id = article.querySelector('a[href*="/status/"] time')?.closest('a')?.getAttribute('href')?.match(/\/status\/(\d+)/)?.[1];
      if (!group || !id) continue;
      let btn = group.querySelector('.taskdock-save');
      if (!btn) {
        const wrap = document.createElement('div');
        wrap.className = 'taskdock-wrap';
        btn = document.createElement('button');
        btn.type = 'button';
        btn.className = 'taskdock-save';
        btn.addEventListener('click', (e) => {
          e.preventDefault();
          e.stopPropagation(); // X opens the post on any click inside it
          const post = postOf(btn.closest('article'));
          if (!post) return;
          if (!send(post)) { btn.title = 'Reload this page to use TaskDock'; return; }
          saved.add(post.id);
          paint(btn);
          askNote(btn, post);
        });
        wrap.append(btn);
        group.append(wrap);
      }
      if (btn.dataset.id !== id) { btn.dataset.id = id; paint(btn); } // X reuses post elements while scrolling
    }
  }

  let open = null;
  function askNote(btn, post) {
    open?.close(false);
    const box = document.createElement('div');
    box.className = 'taskdock-note' + (dark() ? ' is-dark' : '');
    box.innerHTML = '<span>Saved ✓</span><input type="text" placeholder="Add a thought…" aria-label="Your thought about this post (optional)">';
    const input = box.querySelector('input');
    const r = btn.getBoundingClientRect();
    box.style.top = `${Math.min(r.bottom + 6, innerHeight - 52)}px`;
    box.style.left = `${Math.max(8, Math.min(r.left - 120, innerWidth - 380))}px`;
    let timer = setTimeout(() => close(true), 5000);
    let closed = false;
    const close = (keep) => {
      if (closed) return; // removing the field can also fire blur
      closed = true;
      clearTimeout(timer);
      if (keep && input.value.trim()) send({ id: post.id, url: post.url, note: input.value.trim() });
      box.remove();
      if (open?.box === box) open = null;
    };
    open = { box, close };
    for (const ev of ['keydown', 'keyup', 'keypress']) input.addEventListener(ev, (e) => e.stopPropagation()); // X's j/k/l shortcuts
    input.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') close(true);
      else if (e.key === 'Escape') close(false);
    });
    input.addEventListener('input', () => clearTimeout(timer)); // typing keeps it open
    input.addEventListener('blur', () => close(true)); // clicking away keeps what you typed
    document.body.append(box);
    input.focus({ preventScroll: true });
  }

  // X has its own light, dim and dark themes; match the page, not the system.
  function dark() {
    const [r, g, b] = (getComputedStyle(document.body).backgroundColor.match(/\d+/g) ?? [255, 255, 255]).map(Number);
    return r * 0.299 + g * 0.587 + b * 0.114 < 128;
  }

  async function readSaved() {
    const { savedIds = [], pendingPosts = {} } = await chrome.storage.local.get(['savedIds', 'pendingPosts']);
    saved.clear();
    for (const id of [...savedIds, ...Object.keys(pendingPosts)]) saved.add(id);
    document.querySelectorAll('.taskdock-save').forEach(paint);
  }
  chrome.storage.onChanged.addListener((c, area) => {
    if (area === 'local' && (c.savedIds || c.pendingPosts)) readSaved();
  });

  let queued = false;
  new MutationObserver(() => {
    if (queued) return;
    queued = true;
    requestAnimationFrame(() => { queued = false; scan(); });
  }).observe(document.body, { childList: true, subtree: true });
  readSaved().then(scan);
})();
