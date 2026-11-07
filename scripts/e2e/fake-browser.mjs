// Dev-only: runs the real extension/background.js against a fake `chrome` API and the real app
// (scripts/e2e.sh). Plays the user: opens two tabs in the first task window. Writes what it saw to argv[3].
// Usage: node fake-browser.mjs <port> <report.json>
import { writeFileSync } from 'node:fs';

const [port, reportPath] = process.argv.slice(2);
const report = { protocolHello: null, taskWindows: [], restoredTabs: [], blankRemovedAfterRestore: false, minimized: [] };
const save = () => writeFileSync(reportPath, JSON.stringify(report, null, 2));

// The app only accepts extension origins and listens on the test port.
const RealWS = globalThis.WebSocket;
globalThis.WebSocket = class extends RealWS {
  constructor(url) {
    super(url.replace(':47123', `:${port}`), { headers: { Origin: 'chrome-extension://e2e' } });
  }
  send(data) {
    const msg = JSON.parse(data);
    if (msg.type === 'hello') report.protocolHello = msg.v ?? 1;
    super.send(data);
  }
};

const listeners = (name) => {
  const fns = [];
  return { addListener: (fn) => fns.push(fn), fire: (...a) => fns.forEach((f) => f(...a)), name };
};
const ev = {};
for (const n of ['onCreated', 'onUpdated', 'onRemoved', 'onAttached', 'onDetached', 'onMoved']) ev[n] = listeners(n);
const store = {}, sessionStore = {};
const alarm = listeners('alarm');
setInterval(() => alarm.fire(), 1000); // the real alarm retries every 30 s; the app may not be up yet
let nextId = 100;
// One ordinary window full of tabs, in front, like the user's real browser.
const windows = [{ id: 1, focused: true, state: 'normal', tabs: [{ id: 11, url: 'https://old.example/1', active: true }, { id: 12, url: 'https://old.example/2' }] }];
const win = (id) => windows.find((w) => w.id === id);

globalThis.chrome = {
  storage: {
    local: {
      get: async (k) => ({ [k]: store[k] }),
      set: async (o) => Object.assign(store, structuredClone(o)),
      remove: async (k) => { delete store[k]; },
    },
    session: {
      get: async (k) => ({ [k]: sessionStore[k] }),
      set: async (o) => Object.assign(sessionStore, o),
    },
  },
  alarms: { create() {}, onAlarm: alarm },
  runtime: { onStartup: listeners('s'), onInstalled: listeners('i') },
  action: { setBadgeText: async () => {} },
  windows: {
    WINDOW_ID_NONE: -1,
    onFocusChanged: listeners('focus'),
    getAll: async () => structuredClone(windows),
    get: async (id) => { const w = win(id); if (!w) throw new Error('no window'); return structuredClone(w); },
    update: async (id, change) => { const w = win(id); if (w) Object.assign(w, change); if (change.state === 'minimized') report.minimized.push(id); },
    create: async () => {
      const w = { id: nextId++, focused: true, state: 'normal', tabs: [{ id: nextId++, url: 'chrome://newtab/', active: true }] };
      windows.forEach((o) => (o.focused = false));
      windows.push(w);
      report.taskWindows.push(w.id);
      const first = report.taskWindows.length === 1;
      // Round 1: the user opens two pages in the fresh window.
      if (first) setTimeout(async () => {
        for (const url of ['https://e2e.example/a', 'https://e2e.example/b']) await chrome.tabs.create({ windowId: w.id, url });
      }, 500);
      save();
      return structuredClone(w);
    },
  },
  tabs: {
    ...ev,
    discard: async () => {},
    query: async ({ windowId }) => structuredClone(win(windowId)?.tabs ?? []),
    create: async ({ windowId, url, active }) => {
      const t = { id: nextId++, url, active: !!active };
      win(windowId).tabs.push(t);
      if (report.taskWindows.length > 1 && windowId === report.taskWindows.at(-1)) report.restoredTabs.push(url);
      ev.onCreated.fire(t);
      save();
      return t;
    },
    remove: async (ids) => {
      for (const w of windows) w.tabs = w.tabs.filter((t) => !ids.includes(t.id));
      if (report.taskWindows.length > 1) report.blankRemovedAfterRestore = true;
      save();
    },
  },
};

await import('../../extension/background.js');
save();
setInterval(save, 1000);
