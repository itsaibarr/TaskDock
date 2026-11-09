import { test } from 'node:test';
import assert from 'node:assert/strict';
import { elapsed, taskTabs, postRef, queuePost } from './lib.js';

test('elapsed formats minutes and hours', () => {
  assert.equal(elapsed(0, 59_000), '0m');
  assert.equal(elapsed(0, 25 * 60_000), '25m');
  assert.equal(elapsed(0, 65 * 60_000), '1h 05m');
});

test('taskTabs keeps web pages once, in order', () => {
  const tabs = [{ url: 'https://a.example' }, { url: 'chrome://newtab/' }, { url: 'https://a.example' },
    { url: 'file:///book.pdf' }, { pendingUrl: 'https://b.example', url: '' }];
  assert.deepEqual(taskTabs(tabs), ['https://a.example', 'https://b.example']);
});

test('postRef reads post links and nothing else', () => {
  assert.deepEqual(postRef('https://twitter.com/jack/status/20/photo/1?s=46'),
    { id: '20', handle: 'jack', url: 'https://x.com/jack/status/20' });
  assert.equal(postRef('https://mobile.x.com/a_b/status/123')?.id, '123');
  assert.equal(postRef('https://x.com/jack'), null);
  assert.equal(postRef('https://evil.example/jack/status/20'), null);
  assert.equal(postRef('not a url'), null);
});

test('queuePost keeps queued text when only a note arrives', () => {
  let q = queuePost({}, { id: '20', url: 'u', text: 'the post', partial: false });
  q = queuePost(q, { id: '20', url: 'u', note: 'my take' });
  assert.deepEqual(q['20'], { id: '20', url: 'u', text: 'the post', partial: false, note: 'my take' });
});
