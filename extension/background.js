// Talks to the TaskDock Mac app over ws://127.0.0.1:47123.
// The app sends {type:'state', session} on connect and on every start/finish;
// we reconcile the browser to match it. What to restore lives in storage.local, so it
// survives the service worker sleeping or the browser restarting.
//
// When a task needs the browser: open one fresh window for it, minimize every other
// window and unload ("discard") its tabs until the task ends.

import { taskTabs, postRef, queuePost } from './lib.js';

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
    send({ type: 'hello', v: 2 }); // v2: reports tabs while the task runs
    ping = setInterval(() => send({ type: 'ping' }), 20_000); // keeps the service worker alive
    serial(flushPosts);
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
    if (msg.type === 'saved-ids') serial(() => confirmPosts(msg.ids));
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
  const state = { id: s.id, goal: s.goal, name: s.name, emoji: s.emoji, startedAt: s.startedAt, browser: !!s.browser, tabs: s.tabs ?? [], paused: [], taskWindowId: null };

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
  await adoptTaskWindow(state, (await chrome.windows.create({ focused: true })).id);
}

// Makes this the task's window and reopens the tabs saved when the task last ended.
async function adoptTaskWindow(state, windowId) {
  state.taskWindowId = windowId;
  // Session storage empties when the browser quits, so a window id from before a restart is never trusted.
  await chrome.storage.session.set({ taskWindow: windowId });
  state.tabs ??= []; // sessions saved by an older version have no list
  if (state.tabs.length) {
    const blank = (await chrome.tabs.query({ windowId })).filter((t) => /^chrome:\/\/newtab|^$/.test(t.pendingUrl || t.url || ''));
    for (const [i, url] of state.tabs.entries()) await chrome.tabs.create({ windowId, url, active: i === 0 }).catch(() => {});
    await chrome.tabs.remove(blank.map((t) => t.id)).catch(() => {}); // the empty new-tab page the window opened with
  }
  await setSession(state);
}

chrome.windows.onFocusChanged.addListener((windowId) => {
  if (windowId === chrome.windows.WINDOW_ID_NONE) return;
  serial(async () => {
    const s = await getSession();
    if (!s?.browser || s.taskWindowId != null) return;
    if (!s.paused.some((w) => w.id === windowId)) {
      return adoptTaskWindow(s, windowId); // a window the browser just opened itself: use it
    }
    await chrome.windows.update(windowId, { state: 'minimized' }).catch(() => {}); // macOS reopened an old window
    await openTaskWindow(s);
  });
}, { windowTypes: ['normal'] }); // app/popup windows must never become the task window

// Tell TaskDock the task's tabs whenever they change (debounced), so they're already saved when the
// task ends, even if the browser quits or the service worker is asleep at that moment.
let tabsTimer = null;
function reportTabs() {
  clearTimeout(tabsTimer);
  tabsTimer = setTimeout(() => serial(async () => sendTabs(await getSession())), 1000);
}

// Only the browser hosting the live task window reports, and only that window's tabs.
async function sendTabs(s) {
  if (!s?.browser || s.taskWindowId == null) return;
  if ((await chrome.storage.session.get('taskWindow')).taskWindow !== s.taskWindowId) return; // browser restarted
  const w = await chrome.windows.get(s.taskWindowId, { populate: true }).catch(() => null);
  if (w) send({ type: 'tabs', session: s.id, urls: taskTabs(w.tabs) });
}
chrome.tabs.onCreated.addListener(reportTabs);
chrome.tabs.onUpdated.addListener((_, change) => change.url && reportTabs());
chrome.tabs.onRemoved.addListener((_, info) => info.isWindowClosing || reportTabs()); // closing/quitting keeps the list
chrome.tabs.onAttached.addListener(reportTabs);
chrome.tabs.onDetached.addListener(reportTabs);
chrome.tabs.onMoved.addListener(reportTabs);

async function finish(s) {
  clearTimeout(tabsTimer);
  await sendTabs(s); // last word on the tabs, including changes from the final second
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

// MARK: Saved X posts
// x.js sends a post when you click its ◎ button (and a note if you type one). Saves wait in storage.local
// until the app confirms them with its list of saved ids, so nothing is lost while the app is closed.

const sent = new Map(); // post id → the exact message last sent, so a note added meanwhile isn't dropped

const getPending = async () => (await chrome.storage.local.get('pendingPosts')).pendingPosts ?? {};

async function savePost(post) {
  if (!postRef(post.url) || postRef(post.url).id !== post.id) return;
  await chrome.storage.local.set({ pendingPosts: queuePost(await getPending(), post) });
  await flushPosts();
}

async function flushPosts() {
  if (ws?.readyState !== WebSocket.OPEN) return;
  for (const p of Object.values(await getPending())) {
    const msg = JSON.stringify({ type: 'save-post', ...p });
    sent.set(p.id, msg);
    ws.send(msg);
  }
}

async function confirmPosts(ids) {
  const pending = await getPending();
  for (const id of ids) {
    if (pending[id] && sent.get(id) === JSON.stringify({ type: 'save-post', ...pending[id] })) delete pending[id];
  }
  await chrome.storage.local.set({ pendingPosts: pending, savedIds: ids });
}

chrome.runtime.onMessage.addListener((msg) => {
  if (msg?.type === 'save-post' && msg.post) serial(() => savePost(msg.post));
});

// Fallback when X changes its page and the button doesn't show: right-click a post link, or the page of an open post.
// Only the link is known then; the app fetches the text from X.
const POSTS = ['https://x.com/*/status/*', 'https://twitter.com/*/status/*', 'https://mobile.x.com/*/status/*'];
chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.removeAll(() => {
    chrome.contextMenus.create({ id: 'save-link', title: 'Save post to TaskDock', contexts: ['link'], targetUrlPatterns: POSTS });
    chrome.contextMenus.create({ id: 'save-page', title: 'Save post to TaskDock', contexts: ['page'], documentUrlPatterns: POSTS });
  });
});
chrome.contextMenus.onClicked.addListener((info) => {
  const ref = postRef(info.linkUrl ?? info.pageUrl ?? '');
  if (ref) serial(() => savePost({ id: ref.id, url: ref.url, handle: ref.handle }));
});
