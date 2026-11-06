// Pure helpers, shared by the extension and its tests.

export function elapsed(startedAt, now = Date.now()) {
  const m = Math.max(0, Math.floor((now - startedAt) / 60000));
  return m < 60 ? `${m}m` : `${Math.floor(m / 60)}h ${String(m % 60).padStart(2, '0')}m`;
}
