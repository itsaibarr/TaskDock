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
