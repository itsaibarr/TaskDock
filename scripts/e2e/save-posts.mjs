// Dev-only: plays the browser extension for scripts/e2e-posts.sh. Saves a post, adds a note, saves a link-only
// post and sends one forged message, checking the app answers each save with its saved ids.
// Usage: node save-posts.mjs <port>
const port = process.argv[2];
let ws;
for (let i = 0; i < 40 && !ws; i++) {
  try {
    ws = await new Promise((ok, fail) => {
      const s = new WebSocket(`ws://127.0.0.1:${port}`, { headers: { Origin: 'chrome-extension://e2e' } });
      s.onopen = () => ok(s);
      s.onerror = fail;
    });
  } catch { await new Promise((r) => setTimeout(r, 250)); }
}
if (!ws) throw new Error('app not reachable');
const replies = [];
ws.onmessage = (e) => { const m = JSON.parse(e.data); if (m.type === 'saved-ids') replies.push(m.ids); };
const send = async (msg) => { const n = replies.length; ws.send(JSON.stringify({ type: 'save-post', ...msg })); while (replies.length === n) await new Promise((r) => setTimeout(r, 50)); return replies.at(-1); };

const check = (ok, what) => { console.log(`${ok ? 'PASS' : 'FAIL'} ${what}`); if (!ok) process.exitCode = 1; };
let ids = await send({ id: '20', url: 'https://x.com/jack/status/20', handle: 'jack', author: 'Jack Dorsey', text: 'just setting up my twttr', postedAt: '2006-03-21T20:50:14.000Z', partial: false });
check(ids.includes('20'), 'browser save is confirmed with its id');
ids = await send({ id: '20', url: 'https://x.com/jack/status/20', note: 'first post ever' });
check(ids.length === 1, 'a note for a saved post adds no second entry');
ids = await send({ id: '21', url: 'https://twitter.com/jack/status/21?s=46', handle: 'jack' });
check(ids.includes('21'), 'right-click save (link only) is confirmed');
ids = await send({ id: '999', url: 'https://x.com/jack/status/20', text: 'forged' });
check(!ids.includes('999') && ids.length === 2, 'a message whose id does not match its link is ignored');
ws.close();
