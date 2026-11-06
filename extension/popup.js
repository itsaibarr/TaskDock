import { elapsed } from './lib.js';

const { session } = await chrome.storage.local.get('session');
const { connected } = await chrome.storage.session.get('connected');

if (session) {
  document.getElementById('task').hidden = false;
  document.getElementById('meta').textContent = `${session.emoji} ${session.name} · ${elapsed(session.startedAt)}`;
  document.getElementById('goal').textContent = session.goal;
} else {
  document.getElementById('idle').hidden = false;
}
document.getElementById('status').textContent = connected
  ? '● Connected to TaskDock'
  : '○ TaskDock app is not running';
