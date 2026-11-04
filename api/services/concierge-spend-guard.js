// The one spend guard for every path that moves concierge money out, applying both the
// per-transaction and the rolling daily cap — call sites that reimplement it forget the daily half.
const { checkSpendLimit, capCurrency, convertAmount } = require('./money-guard');

const SPEND_DAY_KEY = 'concierge_account.spend_day';

// `currency` is what `amount` is expressed in, normalized to the cap currency before the cap
// math and before the rolling tally, so the daily total stays single-currency. Omitted, the
// amount is treated as already in the cap currency. `record: false` checks without consuming
// budget — reaching a payment step is not spending, and aborted attempts must not eat the cap.
async function guardConciergeSpend(supabase, userId, amount, currency = null, { record = true } = {}) {
  const capCur = capCurrency();
  const normalized = convertAmount(amount, currency || capCur, capCur);
  if (normalized === null) {
    return { ok: false, error: `Can't convert ${String(currency || capCur).toUpperCase()} into the ${capCur} spend cap — refusing to guess an exchange rate.` };
  }
  const today = new Date().toISOString().slice(0, 10); // YYYY-MM-DD (UTC)
  const { data, error } = await supabase
    .from('preferences')
    .select('value')
    .eq('user_id', userId)
    .eq('key', SPEND_DAY_KEY);
  // An unreadable tally must not read as "nothing spent today": that silently resets the cap.
  if (error) {
    return { ok: false, error: 'The daily spend total could not be read, so no money was moved.' };
  }
  let tally = {};
  try { tally = JSON.parse(data?.[0]?.value || '{}'); } catch { tally = {}; }
  const spentToday = tally.date === today ? Number(tally.total) || 0 : 0;
  const verdict = checkSpendLimit({ amount: normalized, spentToday });
  if (!verdict.ok) return verdict;
  if (!record) return { ok: true, spentToday };
  return recordConciergeSpend(supabase, userId, amount, currency, { normalized, today, spentToday });
}

// Adds a completed (or bank-pending) charge to today's tally. Called only after the money
// actually moved, so a declined card or a missing rail no longer eats the daily cap.
async function recordConciergeSpend(supabase, userId, amount, currency = null, context = {}) {
  const capCur = capCurrency();
  const normalized = context.normalized ?? convertAmount(amount, currency || capCur, capCur);
  if (normalized === null) {
    return { ok: false, error: `Can't convert ${String(currency || capCur).toUpperCase()} into the ${capCur} spend cap — refusing to guess an exchange rate.` };
  }
  const today = context.today || new Date().toISOString().slice(0, 10);
  let spentToday = context.spentToday;
  if (spentToday === undefined) {
    const { data, error } = await supabase
      .from('preferences')
      .select('value')
      .eq('user_id', userId)
      .eq('key', SPEND_DAY_KEY);
    if (error) return { ok: false, error: 'The daily spend total could not be read, so it was not recorded.' };
    let tally = {};
    try { tally = JSON.parse(data?.[0]?.value || '{}'); } catch { tally = {}; }
    spentToday = tally.date === today ? Number(tally.total) || 0 : 0;
  }
  const total = Math.round((spentToday + normalized) * 100) / 100;
  const { error: writeError } = await supabase
    .from('preferences')
    .upsert({
      user_id: userId,
      key: SPEND_DAY_KEY,
      value: JSON.stringify({ date: today, total }),
      updated_at: new Date().toISOString(),
    }, { onConflict: 'user_id,key' });
  if (writeError) return { ok: false, error: 'The daily spend total could not be recorded.' };
  return { ok: true, total };
}

module.exports = { guardConciergeSpend, recordConciergeSpend, SPEND_DAY_KEY };
