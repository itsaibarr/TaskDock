import { test } from 'node:test';
import assert from 'node:assert/strict';
import { elapsed, taskTabs } from './lib.js';

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
