// User-saved routines: a named prompt a user can save and re-run later. Simple CRUD
// (create/list/delete) over the `routines` table (supabase-migration-routines.sql).
// Best-effort: never throws, since a storage failure here must never crash a request.

async function createRoutine(supabase, { userId, name, prompt, intervalMinutes = null }) {
  try {
    const nextRunAt = intervalMinutes ? new Date(Date.now() + intervalMinutes * 60000).toISOString() : null;
    const { data, error } = await supabase
      .from('routines')
      .insert({ user_id: userId, name, prompt, interval_minutes: intervalMinutes, next_run_at: nextRunAt })
      .select()
      .single();
    if (error) return { error };
    return data;
  } catch (err) {
    return { error: err.message };
  }
}

async function listDueRoutines(supabase, now) {
  try {
    const { data, error } = await supabase
      .from('routines')
      .select('*')
      .not('interval_minutes', 'is', null)
      // An imported automation arrives with enabled=false so it can't double-fire against
      // its still-live source (see supabase-migration-agent-continuity.sql) — the DB index
      // already assumes this filter; enforce it here too.
      .eq('enabled', true)
      .lte('next_run_at', now.toISOString());
    if (error || !data) return [];
    return data;
  } catch (err) {
    return [];
  }
}

// `outcome.success` distinguishes a real completion from a run that stopped early (loop
// error, unfinished tool calls) — a routine that keeps failing must be visibly failing, not
// silently look identical to one that keeps succeeding just because next_run_at moved on.
// next_run_at always advances regardless of outcome: no retry backoff here (an unattended
// failure retrying every sweep interval instead of its normal cadence is its own runaway-cost
// risk). After ROUTINE_PAUSE_AFTER failures in a row the routine is switched off and the
// caller tells the person. A spend-cap skip advances the schedule without counting a failure.
const ROUTINE_PAUSE_AFTER = 3;

async function markRoutineRun(supabase, routineId, now, outcome = { success: true }) {
  try {
    // The status columns come from a later migration. If it has not been applied, the routine must
    // still move on to its next run: failing to record a run once made every sweep re-run it.
    let routine = null;
    let hasStatusColumns = true;
    const full = await supabase.from('routines').select('interval_minutes, consecutive_failures, user_id, name, enabled').eq('id', routineId).single();
    if (full.error || !full.data) {
      hasStatusColumns = false;
      const basic = await supabase.from('routines').select('interval_minutes').eq('id', routineId).single();
      if (basic.error || !basic.data) return { ok: false, error: basic.error?.message || full.error?.message || 'routine not found' };
      routine = basic.data;
    } else {
      routine = full.data;
    }
    const nextRunAt = new Date(now.getTime() + routine.interval_minutes * 60000).toISOString();
    const success = outcome?.success !== false && !outcome?.spendCapped;
    const countFailure = outcome?.success === false && !outcome?.spendCapped;
    const failures = countFailure
      ? (Number(routine.consecutive_failures) || 0) + 1
      : (success ? 0 : (Number(routine.consecutive_failures) || 0));
    let paused = Boolean(hasStatusColumns && countFailure && failures >= ROUTINE_PAUSE_AFTER);
    const patch = { last_run_at: now.toISOString(), next_run_at: nextRunAt };
    if (hasStatusColumns && !outcome?.spendCapped) {
      Object.assign(patch, {
        last_run_status: success ? 'success' : 'failed',
        last_run_error: success ? null : String(outcome?.error || 'Routine did not complete.').slice(0, 500),
        consecutive_failures: failures
      });
      if (paused) patch.enabled = false;
    }
    let { error } = await supabase.from('routines').update(patch).eq('id', routineId);
    if (error && hasStatusColumns) {
      paused = false;
      ({ error } = await supabase.from('routines').update({ last_run_at: patch.last_run_at, next_run_at: patch.next_run_at }).eq('id', routineId));
    }
    if (error) return { ok: false, error };
    return {
      ok: true,
      paused,
      failures,
      name: routine.name || null,
      userId: routine.user_id || null,
      error: success ? null : String(outcome?.error || '')
    };
  } catch (err) {
    return { ok: false, error: err.message };
  }
}

async function listRoutines(supabase, userId) {
  try {
    const { data, error } = await supabase
      .from('routines')
      .select('*')
      .eq('user_id', userId)
      .order('created_at');
    if (error) return { routines: [], error };
    return { routines: data };
  } catch (err) {
    return { routines: [], error: err.message };
  }
}

async function deleteRoutine(supabase, userId, routineId) {
  try {
    const { error } = await supabase
      .from('routines')
      .delete()
      .eq('id', routineId)
      .eq('user_id', userId);
    if (error) return { ok: false, error };
    return { ok: true };
  } catch (err) {
    return { ok: false, error: err.message };
  }
}

module.exports = { createRoutine, listRoutines, deleteRoutine, listDueRoutines, markRoutineRun, ROUTINE_PAUSE_AFTER };
