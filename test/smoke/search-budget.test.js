const test = require('node:test');
const assert = require('node:assert');
process.env.SUPABASE_URL ||= 'http://127.0.0.1:1';
process.env.SUPABASE_KEY ||= 'test-key';
const { createSearchBudget, normaliseQuery } = require('../../api/services/search-budget');
const { handlers } = require('../../api/actions/browser');

test('a repeated search is answered from memory, ignoring case and punctuation', () => {
  const budget = createSearchBudget();
  budget.record('u', 'Tallest building in Manchester?', 'Deansgate Square South Tower, 201 m');
  assert.strictEqual(budget.cached('u', 'tallest   building in manchester'), 'Deansgate Square South Tower, 201 m');
  assert.strictEqual(budget.cached('other-user', 'tallest building in manchester'), null);
  assert.strictEqual(normaliseQuery('A, b!  C'), 'a b c');
});

test('remembered answers expire', () => {
  let t = 0;
  const budget = createSearchBudget({ ttlMs: 1000, now: () => t });
  budget.record('u', 'a query', 'answer');
  assert.strictEqual(budget.cached('u', 'a query'), 'answer');
  t = 2000;
  assert.strictEqual(budget.cached('u', 'a query'), null);
});

test('web_search answers a repeated query once and never refuses a new one', async () => {
  let calls = 0;
  const deps = { FAST_MODEL: 'x', webSearchBrain: async () => { calls += 1; return `Result number ${calls}: a long enough answer about the thing that was asked.`; } };
  const ctx = { userMessage: "men's" };
  const run = (query, userId = 'budget-user') => handlers.web_search({ userId, params: { query }, context: ctx, deps });
  const first = await run('best kettle uk');
  const again = await run('Best kettle, UK');
  assert.strictEqual(first.success, true);
  assert.strictEqual(again.cached, true);
  assert.strictEqual(calls, 1);
  const results = await Promise.all(Array.from({ length: 12 }, (_, i) => run(`distinct query ${i}`)));
  assert.ok(results.every(r => r.success === true), 'every distinct search ran');
  assert.strictEqual(calls, 13);
});
