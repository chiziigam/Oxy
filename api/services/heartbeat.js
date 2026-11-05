'use strict';

// Adam's heartbeat: runs the proactive sweep (reminders, watches, briefings, deliveries) on a timer.
// On in production unless OXY_HEARTBEAT=off, so a laptop running the server never sweeps the live
// database, and a Fly machine does even if the flag was left out of the environment.

const DEFAULT_INTERVAL_MINUTES = 5;
const FIRST_RUN_DELAY_MS = 60 * 1000;
const DAY_MS = 24 * 60 * 60 * 1000;

function heartbeatEnabled(env = process.env) {
  const flag = String(env.OXY_HEARTBEAT || '').trim().toLowerCase();
  if (flag === 'off' || flag === '0' || flag === 'false') return false;
  if (flag === 'on' || flag === '1' || flag === 'true') return true;
  return String(env.NODE_ENV || '').toLowerCase() === 'production';
}

function heartbeatSettings(env = process.env) {
  const enabled = heartbeatEnabled(env);
  const minutes = Number(env.OXY_HEARTBEAT_MINUTES);
  const intervalMinutes = Number.isFinite(minutes) && minutes >= 1 ? minutes : DEFAULT_INTERVAL_MINUTES;
  return { enabled, intervalMs: intervalMinutes * 60 * 1000 };
}

const RETENTION_INTERVAL_MS = 24 * 60 * 60 * 1000;
const RETENTION_FIRST_DELAY_MS = 10 * 60 * 1000;

// The retention sweep runs daily wherever the heartbeat runs. It used to be a CLI nobody
// scheduled, while /privacy published deletion dates that never happened.
function retentionSettings(env = process.env) {
  const enabled = String(env.OXY_HEARTBEAT || '').toLowerCase() === 'on';
  const minutes = Number(env.OXY_RETENTION_MINUTES);
  const intervalMs = Number.isFinite(minutes) && minutes >= 60 ? minutes * 60 * 1000 : RETENTION_INTERVAL_MS;
  return { enabled, intervalMs, firstRunDelayMs: RETENTION_FIRST_DELAY_MS };
}

function startHeartbeat({
  sweep,
  intervalMs = DEFAULT_INTERVAL_MINUTES * 60 * 1000,
  firstRunDelayMs = FIRST_RUN_DELAY_MS,
  logger = console,
  timers = { setTimeout, setInterval, clearTimeout, clearInterval }
} = {}) {
  let running = false;

  async function tick() {
    if (running) return { skipped: true };
    running = true;
    try {
      const summary = await sweep(logger);
      logger.log?.(`[heartbeat] ${JSON.stringify(summary)}`);
      return { summary };
    } catch (error) {
      logger.error?.(`[heartbeat] sweep failed: ${error.message}`);
      return { error };
    } finally {
      running = false;
    }
  }

  const first = timers.setTimeout(tick, firstRunDelayMs);
  const repeat = timers.setInterval(tick, intervalMs);
  first.unref?.();
  repeat.unref?.();

  return { tick, stop() { timers.clearTimeout(first); timers.clearInterval(repeat); } };
}

// Daily retention. Same overlap guard as the heartbeat. The sweep is idempotent, so a restart
// that runs it again the same day only deletes rows that are already due.
function startDailyJob({
  job,
  intervalMs = DAY_MS,
  firstRunDelayMs = 2 * 60 * 1000,
  logger = console,
  label = 'retention',
  timers = { setTimeout, setInterval, clearTimeout, clearInterval }
} = {}) {
  let running = false;

  async function tick() {
    if (running) return { skipped: true };
    running = true;
    try {
      const summary = await job(logger);
      logger.log?.(`[${label}] ${JSON.stringify(summary)}`);
      return { summary };
    } catch (error) {
      logger.error?.(`[${label}] failed: ${error.message}`);
      return { error };
    } finally {
      running = false;
    }
  }

  const first = timers.setTimeout(tick, firstRunDelayMs);
  const repeat = timers.setInterval(tick, intervalMs);
  first.unref?.();
  repeat.unref?.();
  return { tick, stop() { timers.clearTimeout(first); timers.clearInterval(repeat); } };
}

module.exports = { heartbeatSettings, heartbeatEnabled, retentionSettings, startHeartbeat, startDailyJob, DEFAULT_INTERVAL_MINUTES, DAY_MS };
