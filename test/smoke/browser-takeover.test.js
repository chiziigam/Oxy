'use strict';
// The takeover link is the one place a person can act on a live browser session, so what it
// accepts matters: a signed, short-lived token and nothing else.

require('dotenv').config();

const assert = require('node:assert/strict');
const test = require('node:test');

const takeover = require('../../api/services/browser-takeover');

test('a takeover link carries the user and reads back as a claim', () => {
  const url = takeover.createTakeoverUrl('person-1');
  assert.match(url, /^\/takeover\/[^/]+\.[^/]+$/);
  const token = url.split('/').pop();
  const claim = takeover.readTakeoverToken(token);
  assert.equal(claim.userId, 'person-1');
});

test('a token signed for something else is refused', () => {
  const { signPayload } = require('../../auth');
  const other = signPayload({ type: 'google_oauth', userId: 'person-1' }, 60_000);
  assert.equal(takeover.readTakeoverToken(other), null);
});

test('a tampered or malformed token is refused', () => {
  const token = takeover.createTakeoverUrl('person-1').split('/').pop();
  const [payload, signature] = token.split('.');
  assert.equal(takeover.readTakeoverToken(`${payload}.${signature.slice(0, -2)}xx`), null);
  assert.equal(takeover.readTakeoverToken('nonsense'), null);
  assert.equal(takeover.readTakeoverToken(''), null);
});

test('an expired token is refused', () => {
  const { signPayload } = require('../../auth');
  const expired = signPayload({ type: 'browser_takeover', userId: 'person-1' }, -1000);
  assert.equal(takeover.readTakeoverToken(expired), null);
});

test('the handover page is a phone-sized live view with the three actions', () => {
  const html = takeover.pageHtml();
  assert.match(html, /Adam needs a hand/);
  assert.match(html, /\/frame/);
  assert.match(html, /type: 'click'/);
  assert.match(html, /type: 'type'/);
  assert.match(html, /type: 'done'/);
});
