'use strict';
// The merge rules. The interesting cases are the ones where an address exists but was never
// proven — that is exactly where a careless merge hands someone else's account over.

require('dotenv').config();

const assert = require('node:assert/strict');
const test = require('node:test');

const linking = require('../../api/services/account-linking');

function fakeSupabase({ users = [], prefs = [] } = {}) {
  const state = { users: [...users], prefs: [...prefs], updates: [], upserts: [] };
  return {
    state,
    from(table) {
      const query = {
        _eq: {},
        _ilike: null,
        select() { return query; },
        eq(column, value) { query._eq[column] = value; return query; },
        ilike(column, value) { query._ilike = { column, value: String(value).replace(/\\/g, '') }; return query; },
        limit() { return query; },
        maybeSingle() {
          const rows = state.prefs.filter((p) => p.key === query._eq.key && p.value === query._eq.value);
          return Promise.resolve({ data: rows[0] ? { user_id: rows[0].user_id } : null });
        },
        update(patch) { state.updates.push({ ...query._eq, patch }); return { eq: () => Promise.resolve({ error: null }) }; },
        upsert(row) { state.upserts.push(row); state.prefs.push(row); return Promise.resolve({ error: null }); },
        then(resolve) {
          if (table === 'users') {
            const rows = query._ilike
              ? state.users.filter((u) => String(u.email || '').toLowerCase() === query._ilike.value.toLowerCase())
              : state.users;
            return resolve({ data: rows });
          }
          if (table === 'preferences') return resolve({ data: [] });
          return resolve({ data: [] });
        }
      };
      return query;
    }
  };
}

const derive = (subject) => `apple_${subject}`;

test('a returning provider sign-in lands on the same account', async () => {
  const supabase = fakeSupabase({ prefs: [{ user_id: 'person-1', key: 'auth.apple.subject', value: 'sub-1' }] });
  const result = await linking.resolveOrMergeAccount(supabase, {
    provider: 'apple', subject: 'sub-1', email: 'a@example.com', emailVerified: true, deriveUserId: derive
  });
  assert.equal(result.userId, 'person-1');
  assert.equal(result.created, false);
  assert.equal(result.merged, false);
});

test('an existing account on a verified address is merged into, not duplicated', async () => {
  const supabase = fakeSupabase({
    users: [{ user_id: 'person-2', email: 'b@example.com', email_verified: true, password_hash: 'kept' }]
  });
  const result = await linking.resolveOrMergeAccount(supabase, {
    provider: 'apple', subject: 'sub-2', email: 'b@example.com', emailVerified: true, deriveUserId: derive
  });
  assert.equal(result.userId, 'person-2');
  assert.equal(result.merged, true);
  assert.equal(result.created, false);
  assert.equal(supabase.state.updates.length, 0, 'a verified account keeps its password');
});

test('merging into an unverified account keeps its password', async () => {
  const supabase = fakeSupabase({
    users: [{ user_id: 'owner', email: 'c@example.com', email_verified: false, password_hash: 'their-own-password' }]
  });
  const result = await linking.resolveOrMergeAccount(supabase, {
    provider: 'apple', subject: 'sub-3', email: 'c@example.com', emailVerified: true, deriveUserId: derive
  });
  assert.equal(result.userId, 'owner', 'the account is reused, not duplicated');
  assert.equal(result.merged, true);
  assert.equal(result.passwordRetired, undefined);
  const update = supabase.state.updates[0];
  assert.equal(update.patch.email_verified, true, 'the address is now proven');
  assert.equal(update.patch.password_hash, undefined, 'the password is untouched');
});

test('a brand new person gets a new account and is linked after creation', async () => {
  const supabase = fakeSupabase();
  const result = await linking.resolveOrMergeAccount(supabase, {
    provider: 'apple', subject: 'sub-4', email: 'd@example.com', emailVerified: true, deriveUserId: derive
  });
  assert.equal(result.userId, 'apple_sub-4');
  assert.equal(result.created, true);
  assert.equal(supabase.state.upserts.length, 0, 'no link is written before the account row exists');
});

test('with no email, a new account is created rather than guessing a match', async () => {
  const supabase = fakeSupabase({ users: [{ user_id: 'someone', email: 'e@example.com', email_verified: true }] });
  const result = await linking.resolveOrMergeAccount(supabase, {
    provider: 'apple', subject: 'sub-5', email: null, emailVerified: false, deriveUserId: derive
  });
  assert.equal(result.created, true);
  assert.equal(result.userId, 'apple_sub-5');
});
