'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const test = require('node:test');

const { sessionRevocationDecision } = require('../../auth');
const { createSpendCap, USER_MESSAGE, capFromEnv } = require('../../api/services/spend-cap');
const { createLimiter } = require('../../api/services/cost-route-limits');
const { missedReminderNotice } = require('../../api/services/scheduled-tasks');
const { buildToolsForGemini, getActionContract } = require('../../api/action-contracts');
const { startDailyJob } = require('../../api/services/heartbeat');

test('a session lookup error rejects the request and does not look like a logout', () => {
  const decision = sessionRevocationDecision({ lookupError: new Error('timeout'), userRow: null, tokenVersion: 1 });
  assert.equal(decision.ok, false);
  assert.equal(decision.status, 503);
  assert.match(decision.error, /could not be checked/i);
});

test('a missing account or a rotated token is still a 401', () => {
  assert.equal(sessionRevocationDecision({ userRow: null, tokenVersion: 1 }).status, 401);
  assert.equal(sessionRevocationDecision({ userRow: { token_version: 2 }, tokenVersion: 1 }).status, 401);
  assert.equal(sessionRevocationDecision({ userRow: { token_version: 4 }, tokenVersion: 4 }).ok, true);
});

test('the daily model cap blocks the next call and says so in plain language', () => {
  const warnings = [];
  const at = new Date('2026-11-01T12:00:00Z');
  const cap = createSpendCap({
    capUsd: 1,
    spikeUsd: 0.4,
    now: () => at,
    logger: { warn: message => warnings.push(message) }
  });
  assert.equal(cap.status('u1', at).blocked, false);
  cap.charge('u1', 0.6, at);
  assert.equal(cap.status('u1', at).blocked, false);
  cap.charge('u1', 0.5, at);
  assert.equal(cap.status('u1', at).blocked, true);
  assert.equal(cap.status('u2', at).blocked, false);
  const nextDay = new Date('2026-11-02T12:00:00Z');
  assert.equal(cap.status('u1', nextDay).blocked, false);
  assert.ok(warnings.some(line => line.includes('user=u1') && line.includes('cap=$1')));
  assert.equal(USER_MESSAGE, "That's as far as I can go today. It resets tomorrow.");
  assert.equal(capFromEnv({}), 2);
  assert.equal(capFromEnv({ OXY_DAILY_SPEND_CAP_USD: '0' }), 0);
});

test('a zero cap does not block anyone', () => {
  const cap = createSpendCap({ capUsd: 0, now: () => new Date('2026-11-01T00:00:00Z') });
  cap.charge('u1', 50, new Date('2026-11-01T00:00:00Z'));
  assert.equal(cap.status('u1').blocked, false);
});

test('the paid lookup routes stop answering after their limit', () => {
  let clock = 1_000;
  const limit = createLimiter({ max: 2, windowMs: 100, now: () => clock });
  const seen = [];
  function hit() {
    const res = {
      statusCode: 200,
      status(code) { this.statusCode = code; return this; },
      json(body) { this.body = body; }
    };
    let nexted = false;
    limit({ auth: { userId: 'u1' } }, res, () => { nexted = true; });
    seen.push({ nexted, statusCode: res.statusCode });
  }
  hit();
  hit();
  hit();
  assert.deepEqual(seen.map(item => item.nexted), [true, true, false]);
  assert.equal(seen[2].statusCode, 429);
  clock += 200;
  hit();
  assert.equal(seen[3].nexted, true);
});

test('the four cost routes are actually wrapped in their limiters', () => {
  const src = fs.readFileSync(require.resolve('../../api/index.js'), 'utf8');
  assert.match(src, /app\.post\('\/tts-preview', ttsPreviewLimit/);
  assert.match(src, /app\.post\('\/geocode', requireSessionAuth, geocodeLimit/);
  assert.match(src, /app\.post\('\/home-addresses', requireSessionAuth, homeAddressLimit/);
  assert.match(src, /app\.post\('\/proactive\/:userId\/run', proactiveRunLimit/);
});

test('a late one-shot reminder is told to the person instead of closed in silence', () => {
  const notice = missedReminderNotice({ title: 'Call the dentist' });
  assert.equal(notice.kind, 'reminder_missed');
  assert.match(notice.body, /I missed “Call the dentist”/);
  assert.match(notice.body, /more than an hour ago/);
});

test('stripe payout is not a tool the model can call, and it stays review-gated', () => {
  const names = buildToolsForGemini(false)[0].functionDeclarations.map(item => item.name);
  assert.equal(names.includes('stripe_payout_to_user'), false);
  const contract = getActionContract('stripe_payout_to_user');
  assert.equal(contract.modelVisible, false);
  assert.equal(contract.availability, 'unavailable');
  assert.equal(contract.executionMode, 'review');
});

test('retention is scheduled as a daily in-process job', () => {
  const src = fs.readFileSync(require.resolve('../../server.js'), 'utf8');
  assert.match(src, /startDailyJob\(\{ job: \(\) => app\.runRetentionSweep/);
  const handles = [];
  const timers = {
    setTimeout: (fn, ms) => { const h = { fn, ms }; handles.push(h); return h; },
    setInterval: (fn, ms) => { const h = { fn, ms }; handles.push(h); return h; },
    clearTimeout() {},
    clearInterval() {}
  };
  startDailyJob({ job: async () => ({ purged: 1 }), logger: { log() {}, error() {} }, timers, firstRunDelayMs: 5, intervalMs: 9 });
  assert.equal(handles[0].ms, 5);
  assert.equal(handles[1].ms, 9);
});

test('reminder, calendar, email and browser guidance tell the model to act', () => {
  const decls = Object.fromEntries(buildToolsForGemini(false)[0].functionDeclarations.map(item => [item.name, item.description]));
  assert.match(decls.create_reminder, /as soon as they ask to be reminded/);
  assert.match(decls.get_calendar_events, /Read the calendar instead of guessing/);
  assert.match(decls.send_email, /Do not ask whether they want you to send an email/);
  assert.match(decls.browser_open, /before saying a website is out of reach/);
});
