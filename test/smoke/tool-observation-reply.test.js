const assert = require('node:assert/strict');
const test = require('node:test');

process.env.SUPABASE_URL = process.env.SUPABASE_URL || 'https://example.supabase.co';
process.env.SUPABASE_KEY = process.env.SUPABASE_KEY || 'test-key';
process.env.GEMINI_API_KEY = process.env.GEMINI_API_KEY || 'test-key';
process.env.OXY_SESSION_SECRET = process.env.OXY_SESSION_SECRET || 'test-secret';

const {
  isToolObservation, stripToolObservation, sanitizeReply, OBSERVATION_FALLBACK,
} = require('../../api/services/agent-final-answer');
const { reconcileSpokenWithActions } = require('../../api');

// What a browser step reads back to the model ("does jl have mw4").
const OBSERVATION = [
  'Call of Duty: Modern Warfare 4 | John Lewis — https://www.johnlewis.com/search?search-term=mw4',
  'Controls on this page (use the number as elementId):\n#0 "Skip Filters"\n#1 [dropdown, options: "Relevance", "Price low to high"] "Sort by"\n#2 "Add to basket"\n#47 "Homepage"',
  'Page text:\nCall of Duty: Modern Warfare 4 PS5 £59.99 In stock',
].join('\n\n');

const browserStep = {
  action: 'browser_open',
  result: {
    success: true, outcome: 'completed', url: 'https://www.johnlewis.com/search?search-term=mw4',
    pageTitle: 'Call of Duty: Modern Warfare 4 | John Lewis', elements: ['#0 "Skip Filters"'], pageText: '…', text: OBSERVATION,
  },
};

test('a browser observation is recognised and plain sentences are not', () => {
  assert.equal(isToolObservation(OBSERVATION), true);
  assert.equal(isToolObservation('Yes, John Lewis has Call of Duty: Modern Warfare 4 for PS5 at £59.99.'), false);
  assert.equal(isToolObservation('Step #1 is to sign in.'), false);
});

test('stripping keeps the plain answer around a dump and drops the controls', () => {
  const out = stripToolObservation(`Yes, they have it at £59.99.\n\n${OBSERVATION}`);
  assert.equal(out, 'Yes, they have it at £59.99.');
  assert.doesNotMatch(out, /elementId|#47|Skip Filters|https:\/\//);
});

test('a reply that is only a dump becomes a plain fallback, never the dump', () => {
  assert.equal(sanitizeReply(OBSERVATION), OBSERVATION_FALLBACK);
});

test('the model answer is kept and the observation is never used as the reply', () => {
  const plain = 'Yes, John Lewis has Call of Duty: Modern Warfare 4 for PS5 at £59.99. https://www.johnlewis.com/mw4';
  assert.equal(reconcileSpokenWithActions(plain, [browserStep]), plain);
  const empty = reconcileSpokenWithActions('', [browserStep]);
  assert.doesNotMatch(String(empty), /Controls on this page|elementId|#0 "Skip Filters"/);
  const echoed = reconcileSpokenWithActions(OBSERVATION, [browserStep]);
  assert.doesNotMatch(String(echoed), /Controls on this page|elementId|#47/);
});
