// Pure helpers, shared by the extension and its tests.

export function elapsed(startedAt, now = Date.now()) {
  const m = Math.max(0, Math.floor((now - startedAt) / 60000));
  return m < 60 ? `${m}m` : `${Math.floor(m / 60)}h ${String(m % 60).padStart(2, '0')}m`;
}

// The task window's web pages (http/https; extensions can't open file: links by default), in order, without duplicates.
export function taskTabs(tabs) {
  const urls = tabs.map((t) => t.url || t.pendingUrl || '').filter((u) => /^https?:/.test(u));
  return [...new Set(urls)];
}

// The id, handle and clean link of an x.com / twitter.com post link, or null. Mirrors Post.ref in the app.
export function postRef(url) {
  let u;
  try { u = new URL(url); } catch { return null; }
  if (!/(^|\.)(x|twitter)\.com$/i.test(u.hostname)) return null;
  const m = u.pathname.match(/^\/(\w+)\/status\/(\d+)/);
  return m ? { id: m[2], handle: m[1], url: `https://x.com/${m[1]}/status/${m[2]}` } : null;
}

// Adds a save (or a later note for it) to the queue of saves the app hasn't confirmed yet. Keys a message
// doesn't carry keep their queued value, so a note sent after the save never wipes the post's text.
export function queuePost(pending, post) {
  return { ...pending, [post.id]: { ...pending[post.id], ...post } };
}
