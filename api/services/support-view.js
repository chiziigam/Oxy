'use strict';
// One page that answers "what is happening with this person's account?" without opening SQL.
// Read-only. It shows what support needs — state, usage, what the browser is doing, what failed
// recently — and never a secret, a token or a password hash.

const usageMeter = require('./usage-meter');

function supportUserIds(env = process.env) {
  return String(env.OXY_SUPPORT_USER_IDS || '')
    .split(',')
    .map((id) => id.trim())
    .filter(Boolean);
}

function isSupportAdmin(userId) {
  if (!userId) return false;
  return supportUserIds().includes(userId);
}

async function count(supabase, table, userId, filters = {}) {
  try {
    let query = supabase.from(table).select('*', { count: 'exact', head: true }).eq('user_id', userId);
    for (const [column, value] of Object.entries(filters)) query = query.eq(column, value);
    const { count: total, error } = await query;
    return error ? null : total;
  } catch {
    return null;
  }
}

async function recent(supabase, table, userId, columns, limit = 8) {
  try {
    const { data } = await supabase
      .from(table)
      .select(columns)
      .eq('user_id', userId)
      .order('created_at', { ascending: false })
      .limit(limit);
    return data || [];
  } catch {
    return [];
  }
}

async function snapshot(supabase, userId) {
  const { readToday, capUsd } = require('./user-budget');
  const { usedBytes, capBytes } = require('./storage-quota');

  const account = await (async () => {
    try {
      const { data } = await supabase.from('users').select('email, email_verified, created_at').eq('user_id', userId).maybeSingle();
      return data || null;
    } catch {
      return null;
    }
  })();
  const [conversations, tasks, workflows, documents, memories, connectors] = await Promise.all([
    count(supabase, 'conversations', userId),
    count(supabase, 'agent_tasks', userId),
    count(supabase, 'workflows', userId),
    count(supabase, 'documents', userId),
    count(supabase, 'memories', userId),
    count(supabase, 'connectors', userId),
  ]);

  const usage = await readToday(supabase, userId).catch(() => ({ usd: 0, calls: 0 }));
  const storageUsed = await usedBytes(supabase, userId);

  let browser = null;
  try {
    const { getSession } = require('./browser-session');
    const session = getSession(userId);
    if (session) {
      browser = {
        url: session.page?.url?.() || null,
        site: session.site || null,
        idleSeconds: Math.round((Date.now() - (session.lastActivityAt || Date.now())) / 1000),
        actions: (session.history || []).slice(-5),
      };
    }
  } catch { /* no browser is a normal state */ }

  const actions = await recent(supabase, 'action_log', userId, 'action, status, created_at, error', 8);

  return {
    userId,
    account: account
      ? { email: account.email || null, emailVerified: account.email_verified === true, createdAt: account.created_at || null }
      : null,
    counts: { conversations, tasks, workflows, documents, memories, connectors },
    usage: { todayUsd: Number(usage.usd.toFixed(4)), todayCalls: usage.calls, dailyCapUsd: capUsd() },
    storage: {
      usedMb: Number((storageUsed / 1024 / 1024).toFixed(1)),
      capMb: Math.round(capBytes() / 1024 / 1024),
    },
    browser,
    recentActions: actions.map((row) => {
      let parsed = row.action;
      try { parsed = typeof row.action === 'string' ? JSON.parse(row.action) : row.action; } catch { /* leave as-is */ }
      return {
        at: row.created_at,
        action: parsed?.type || parsed?.action || String(row.action || ''),
        status: row.status,
        error: row.error ? String(row.error).slice(0, 160) : null,
      };
    }),
    serverUsage: usageMeter ? (() => { const u = usageMeter.lifetimeReport(); return { calls: u.calls, usd: u.estimatedUsd }; })() : null
  };
}

const page = (body) => `<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>Support</title>
<style>
  body{margin:0;padding:20px;font:15px/1.45 -apple-system,system-ui,sans-serif;background:#f7f7f9;color:#111}
  @media (prefers-color-scheme:dark){body{background:#000;color:#fff}}
  h1{font-size:19px;margin:0 0 14px} h2{font-size:13px;text-transform:uppercase;letter-spacing:.04em;color:#6b6b70;margin:22px 0 6px}
  table{border-collapse:collapse;width:100%;max-width:760px;background:#fff;border-radius:12px;overflow:hidden}
  @media (prefers-color-scheme:dark){table{background:#1c1c1e}}
  td{padding:9px 12px;border-bottom:1px solid #e6e6ea;vertical-align:top;font-size:14px}
  @media (prefers-color-scheme:dark){td{border-color:#2c2c2e}}
  td:first-child{color:#6b6b70;width:38%}
  form{display:flex;gap:8px;max-width:760px;margin-bottom:8px}
  input{flex:1;padding:11px 12px;border-radius:10px;border:1px solid #c7c7cc;font:15px inherit;background:transparent;color:inherit}
  button{padding:11px 16px;border-radius:10px;border:0;background:#111;color:#fff;font:600 15px inherit}
  @media (prefers-color-scheme:dark){button{background:#fff;color:#000}}
  code{font-size:13px}
</style></head><body>${body}</body></html>`;

function render(data) {
  const rows = (items) => items.map(([label, value]) => `<tr><td>${label}</td><td>${value ?? '—'}</td></tr>`).join('');
  if (!data) return page('<h1>Support</h1><p>No account with that id.</p>');
  const counts = data.counts || {};
  const actions = (data.recentActions || []).map((row) =>
    `<tr><td>${row.at?.slice(0, 19).replace('T', ' ')}</td><td><code>${row.action}</code> ${row.status}${row.error ? ` — ${row.error}` : ''}</td></tr>`
  ).join('') || '<tr><td colspan="2">No recent actions.</td></tr>';
  return page(`
    <h1>${data.userId}</h1>
    <h2>Account</h2>
    <table>${rows([
      ['Email', data.account?.email || 'none'],
      ['Email verified', data.account ? String(data.account.emailVerified) : 'no account row'],
      ['Created', data.account?.createdAt?.slice(0, 19).replace('T', ' ')],
    ])}</table>
    <h2>Today</h2>
    <table>${rows([
      ['Inference', `$${data.usage.todayUsd} of $${data.usage.dailyCapUsd} · ${data.usage.todayCalls} calls`],
      ['File storage', `${data.storage.usedMb}MB of ${data.storage.capMb}MB`],
      ['Server lifetime', data.serverUsage ? `${data.serverUsage.calls} calls · $${data.serverUsage.usd}` : '—'],
    ])}</table>
    <h2>What exists</h2>
    <table>${rows(Object.entries(counts).map(([key, value]) => [key, value ?? '—']))}</table>
    <h2>Browser</h2>
    <table>${data.browser
      ? rows([
          ['Page', data.browser.url],
          ['Site', data.browser.site],
          ['Idle', `${data.browser.idleSeconds}s`],
          ['Last steps', (data.browser.actions || []).join(' · ')],
        ])
      : '<tr><td>Open</td><td>No browser session</td></tr>'}</table>
    <h2>Recent actions</h2>
    <table>${actions}</table>
  `);
}

module.exports = { isSupportAdmin, supportUserIds, snapshot, render, page };
