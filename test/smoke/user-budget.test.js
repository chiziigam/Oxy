'use strict';
// The daily ceiling on what one account can spend on inference. It has to refuse politely and
// recover on its own the next day, and it must never turn a storage hiccup into an outage.

require('dotenv').config();

const assert = require('node:assert/strict');
const test = require('node:test');

const budget = require('../../api/services/user-budget');

// A tiny stand-in for the preferences table: user_id + key is unique, value is a string.
function fakeSupabase(store = new Map()) {
  return {
    from() {
      const query = {
        _filters: {},
        _key: null,
        select() { return query; },
        eq(column, value) { query._filters[column] = value; return query; },
        maybeSingle() {
          const row = store.get(`${query._filters.user_id}|${query._filters.key}`);
          return Promise.resolve({ data: row ? { value: row } : null });
        },
        upsert(row) {
          store.set(`${row.user_id}|${row.key}`, row.value);
          return Promise.resolve({ error: null });
        }
      };
      return query;
    }
  };
}

test('a fresh account is under budget', async () => {
  const supabase = fakeSupabase();
  const result = await budget.checkBudget(supabase, 'person-1');
  assert.equal(result.ok, true);
  assert.equal(result.used, 0);
  assert.ok(result.cap > 0);
});

test('spend accumulates and the ceiling stops the next turn', async () => {
  const supabase = fakeSupabase();
  const cap = budget.capUsd();
  await budget.addSpend(supabase, 'person-1', cap / 2, 3);
  let result = await budget.checkBudget(supabase, 'person-1');
  assert.equal(result.ok, true);
  assert.equal(result.calls, 3);

  await budget.addSpend(supabase, 'person-1', cap / 2, 1);
  result = await budget.checkBudget(supabase, 'person-1');
  assert.equal(result.ok, false);
  assert.match(result.error, /daily limit/i);
});

test('one account spending does not touch another', async () => {
  const supabase = fakeSupabase();
  await budget.addSpend(supabase, 'person-1', budget.capUsd(), 1);
  const other = await budget.checkBudget(supabase, 'person-2');
  assert.equal(other.ok, true);
  assert.equal(other.used, 0);
});

test('a broken or unreadable record is read as zero, not as an outage', async () => {
  const supabase = {
    from: () => ({
      select() { return this; },
      eq() { return this; },
      maybeSingle() { return Promise.resolve({ data: { value: 'not json' } }); },
      upsert() { return Promise.resolve({ error: null }); }
    })
  };
  const result = await budget.checkBudget(supabase, 'person-3');
  assert.equal(result.ok, true);
  assert.equal(result.used, 0);
});

test('the day key rolls over', () => {
  const today = budget.dayKey(new Date('2026-11-04T23:00:00Z'));
  const tomorrow = budget.dayKey(new Date('2026-11-05T01:00:00Z'));
  assert.notEqual(today, tomorrow);
  assert.match(today, /^usage\.daily\.2026-11-04$/);
});
