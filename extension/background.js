// Talks to the TaskDock Mac app over ws://127.0.0.1:47123.
// The app sends {type:'state', session} on connect and on every start/finish;
// we reconcile the browser to match it. What to restore lives in storage.local, so it
// survives the service worker sleeping or the browser restarting.
//
// When a task needs the browser: open one fresh window for it, minimize every other
// window and unload ("discard") its tabs until the task ends.

const PORT = 47123;
let ws = null;
let ping = null;
let queue = Promise.resolve();
const serial = (fn) => (queue = queue.then(fn).catch((e) => console.error('TaskDock:', e)));

const getSession = async () => (await chrome.storage.local.get('session')).session ?? null;
const setSession = (session) =>
  session ? chrome.storage.local.set({ session }) : chrome.storage.local.remove('session');

// MARK: Connection

function connect() {
  if (ws && ws.readyState <= WebSocket.OPEN) return;
  const sock = (ws = new WebSocket(`ws://127.0.0.1:${PORT}`));
  sock.onopen = () => {
    chrome.storage.session.set({ connected: true });
    send({ type: 'hello' });
    ping = setInterval(() => send({ type: 'ping' }), 20_000); // keeps the service worker alive
  };
  sock.onclose = () => {
    if (ws !== sock) return; // an older socket closing late must not touch the current one
    chrome.storage.session.set({ connected: false });
    clearInterval(ping);
    ws = null;
  };
  sock.onerror = () => {}; // app not running; the alarm retries
  sock.onmessage = (e) => {
    const msg = JSON.parse(e.data);
    if (msg.type === 'state') serial(() => reconcile(msg.session));
  };
}

function send(msg) {
  if (ws?.readyState === WebSocket.OPEN) ws.send(JSON.stringify(msg));
}

chrome.alarms.create('reconnect', { periodInMinutes: 0.5 });
chrome.alarms.onAlarm.addListener(connect);
chrome.runtime.onStartup.addListener(connect);
chrome.runtime.onInstalled.addListener(connect);
connect();

// MARK: Sessions

async function reconcile(next) {
  const current = await getSession();
  if (current?.id === next?.id) return;
  if (current) await finish(current);
  if (next) await start(next);
}

async function start(s) {
  const state = { id: s.id, goal: s.goal, name: s.name, emoji: s.emoji, startedAt: s.startedAt, browser: !!s.browser, paused: [], taskWindowId: null };

  if (s.browser) {
    // TaskDock activates the browser just before telling us; give macOS a moment so
    // "is this browser in front?" is answered correctly.
    await new Promise((r) => setTimeout(r, 600));
    const windows = await chrome.windows.getAll({ windowTypes: ['normal'], populate: true });
    state.paused = windows.map((w) => ({ id: w.id, state: w.state }));
    const frontmost = windows.some((w) => w.focused);
    await setSession(state); // saved before changing anything, so finish can always undo it

    for (const w of windows) {
      if (w.state !== 'minimized') await chrome.windows.update(w.id, { state: 'minimized' }).catch(() => {});
      for (const t of w.tabs) {
        if (!t.active && !t.discarded) await chrome.tabs.discard(t.id).catch(() => {});
      }
    }
    // The fresh window opens once this browser is in front. A second browser that isn't
    // part of the task stays hidden instead of popping up an empty window.
    if (frontmost) await openTaskWindow(state);
  }

  await setSession(state);
  await chrome.action.setBadgeText({ text: s.emoji });
}

async function openTaskWindow(state) {
  state.taskWindowId = (await chrome.windows.create({ focused: true })).id;
  await setSession(state);
}

chrome.windows.onFocusChanged.addListener((windowId) => {
  if (windowId === chrome.windows.WINDOW_ID_NONE) return;
  serial(async () => {
    const s = await getSession();
    if (!s?.browser || s.taskWindowId != null) return;
    if (!s.paused.some((w) => w.id === windowId)) {
      s.taskWindowId = windowId; // a window the browser just opened itself: use it
      return setSession(s);
    }
    await chrome.windows.update(windowId, { state: 'minimized' }).catch(() => {}); // macOS reopened an old window
    await openTaskWindow(s);
  });
}, { windowTypes: ['normal'] }); // app/popup windows must never become the task window

async function finish(s) {
  // Only un-minimize windows that are still minimized, so running this twice (after an
  // interruption) never undoes anything the user did. Clear the session last.
  for (const w of s.paused) {
    if (w.state === 'minimized') continue;
    const now = await chrome.windows.get(w.id).catch(() => null);
    if (now?.state === 'minimized') await chrome.windows.update(w.id, { state: w.state }).catch(() => {});
  }
  await setSession(null);
  await chrome.action.setBadgeText({ text: '' });
}
