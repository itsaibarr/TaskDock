import { test } from 'node:test';
import assert from 'node:assert/strict';
import { elapsed } from './lib.js';

test('elapsed formats minutes and hours', () => {
  assert.equal(elapsed(0, 59_000), '0m');
  assert.equal(elapsed(0, 25 * 60_000), '25m');
  assert.equal(elapsed(0, 65 * 60_000), '1h 05m');
});
