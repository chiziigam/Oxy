'use strict';
// Two guard rails that only matter once real people have accounts: a support view that the wrong
// person cannot open, and a storage ceiling that fails with a sentence rather than a stack trace.

require('dotenv').config();

const assert = require('node:assert/strict');
const test = require('node:test');

const support = require('../../api/services/support-view');
const quota = require('../../api/services/storage-quota');

function fakeSupabase({ byteSizes = [], rows = {} } = {}) {
  return {
    from(table) {
      const query = {
        _filters: {},
        select() { return query; },
        eq(column, value) { query._filters[column] = value; return query; },
        like() { return query; },
        order() { return query; },
        limit() { return query; },
        maybeSingle() {
          const value = rows[`${table}:${query._filters.user_id || ''}`];
          return Promise.resolve({ data: value || null });
        },
        then(resolve) {
          if (table === 'documents') return resolve({ data: byteSizes.map((size) => ({ byte_size: size })) });
          return resolve({ data: [], count: 0 });
        }
      };
      return query;
    }
  };
}

test('support is closed unless the account is on the allowlist', () => {
  const previous = process.env.OXY_SUPPORT_USER_IDS;
  process.env.OXY_SUPPORT_USER_IDS = 'owner-1,owner-2';
  try {
    assert.equal(support.isSupportAdmin('owner-1'), true);
    assert.equal(support.isSupportAdmin('someone-else'), false);
    assert.equal(support.isSupportAdmin(''), false);
    assert.deepEqual(support.supportUserIds(), ['owner-1', 'owner-2']);
  } finally {
    if (previous === undefined) delete process.env.OXY_SUPPORT_USER_IDS;
    else process.env.OXY_SUPPORT_USER_IDS = previous;
  }
});

test('with no allowlist configured nobody can open it', () => {
  const previous = process.env.OXY_SUPPORT_USER_IDS;
  delete process.env.OXY_SUPPORT_USER_IDS;
  try {
    assert.equal(support.isSupportAdmin('owner-1'), false);
    assert.deepEqual(support.supportUserIds(), []);
  } finally {
    if (previous !== undefined) process.env.OXY_SUPPORT_USER_IDS = previous;
  }
});

test('the support page states what it knows and never shows a secret', () => {
  const html = support.render({
    userId: 'person-1',
    account: { email: 'a@example.com', emailVerified: false, createdAt: '2026-11-04T01:00:00Z' },
    counts: { conversations: 3, tasks: 1, documents: 2 },
    usage: { todayUsd: 0.42, todayCalls: 9, dailyCapUsd: 2 },
    storage: { usedMb: 12.5, capMb: 500 },
    browser: { url: 'https://example.com/', site: 'example.com', idleSeconds: 12, actions: ['click #4'] },
    recentActions: [{ at: '2026-11-04T02:00:00Z', action: 'browser_act', status: 'executed', error: null }],
    serverUsage: { calls: 100, usd: 1.2 }
  });
  assert.match(html, /person-1/);
  assert.match(html, /\$0\.42 of \$2/);
  assert.match(html, /12\.5MB of 500MB/);
  assert.match(html, /browser_act/);
  assert.doesNotMatch(html, /password/i);
  assert.doesNotMatch(html, /token/i);
});

test('a missing account still renders a page instead of throwing', () => {
  const html = support.render(null);
  assert.match(html, /No account with that id/);
});

test('storage usage adds up what is stored', async () => {
  const supabase = fakeSupabase({ byteSizes: [1024 * 1024, 2 * 1024 * 1024] });
  assert.equal(await quota.usedBytes(supabase, 'person-1'), 3 * 1024 * 1024);
});

test('an upload over the ceiling is refused with a sentence', async () => {
  const previous = process.env.OXY_USER_STORAGE_MB;
  process.env.OXY_USER_STORAGE_MB = '1';
  try {
    const supabase = fakeSupabase({ byteSizes: [1024 * 1024] });
    const result = await quota.checkQuota(supabase, 'person-1', 1024);
    assert.equal(result.ok, false);
    assert.match(result.error, /used 1MB of its 1MB/);
  } finally {
    if (previous === undefined) delete process.env.OXY_USER_STORAGE_MB;
    else process.env.OXY_USER_STORAGE_MB = previous;
  }
});

test('an upload with room passes and reports the remaining space', async () => {
  const previous = process.env.OXY_USER_STORAGE_MB;
  process.env.OXY_USER_STORAGE_MB = '10';
  try {
    const supabase = fakeSupabase({ byteSizes: [1024 * 1024] });
    const result = await quota.checkQuota(supabase, 'person-1', 1024);
    assert.equal(result.ok, true);
    assert.equal(result.room, 9 * 1024 * 1024);
  } finally {
    if (previous === undefined) delete process.env.OXY_USER_STORAGE_MB;
    else process.env.OXY_USER_STORAGE_MB = previous;
  }
});
