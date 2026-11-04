'use strict';
// A per-person daily ceiling on model spend. Without it one account can burn the whole month's
// inference budget in an afternoon, and the first anyone notices is the provider invoice.
// Stored in `preferences` (user_id + key) so it needs no migration; a failure to read or write
// it never blocks a turn — a missing budget must not become an outage.

function capUsd(env = process.env) {
  const value = Number(env.OXY_USER_DAILY_USD);
  return Number.isFinite(value) && value > 0 ? value : 2;
}

function dayKey(now = new Date()) {
  return `usage.daily.${now.toISOString().slice(0, 10)}`;
}

function parseRow(row) {
  if (!row?.value) return { usd: 0, calls: 0 };
  try {
    const parsed = JSON.parse(row.value);
    return { usd: Number(parsed.usd) || 0, calls: Number(parsed.calls) || 0 };
  } catch {
    return { usd: 0, calls: 0 };
  }
}

async function readToday(supabase, userId) {
  if (!supabase || !userId) return { usd: 0, calls: 0 };
  try {
    const { data } = await supabase
      .from('preferences')
      .select('value')
      .eq('user_id', userId)
      .eq('key', dayKey())
      .maybeSingle();
    return parseRow(data);
  } catch {
    return { usd: 0, calls: 0 };
  }
}

// Before the work starts: is this person already past today's ceiling?
async function checkBudget(supabase, userId) {
  const used = await readToday(supabase, userId);
  const cap = capUsd();
  return {
    ok: used.usd < cap,
    used: Number(used.usd.toFixed(4)),
    cap,
    calls: used.calls,
    error: used.usd < cap
      ? null
      : `That's the daily limit for this account ($${cap.toFixed(2)}). It resets tomorrow.`
  };
}

async function addSpend(supabase, userId, usd, calls = 1) {
  if (!supabase || !userId) return;
  const amount = Number(usd) || 0;
  if (amount <= 0 && !calls) return;
  try {
    const used = await readToday(supabase, userId);
    const next = { usd: Number((used.usd + amount).toFixed(6)), calls: used.calls + calls };
    await supabase
      .from('preferences')
      .upsert(
        { user_id: userId, key: dayKey(), value: JSON.stringify(next) },
        { onConflict: 'user_id,key' }
      );
  } catch (error) {
    console.warn('[user-budget] could not record spend:', error.message);
  }
}

module.exports = { checkBudget, addSpend, readToday, capUsd, dayKey };
