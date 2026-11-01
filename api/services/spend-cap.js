'use strict';

// Per-user daily model spend. In memory on this process: one Fly machine is the deployment,
// and a restart starts the day again. OXY_DAILY_SPEND_CAP_USD=0 turns the cap off.

const USER_MESSAGE = "That's as far as I can go today. It resets tomorrow.";
const DEFAULT_CAP_USD = 2;
const DEFAULT_SPIKE_USD = 0.5;

function dayKey(now, timeZone) {
  try {
    return new Intl.DateTimeFormat('en-CA', {
      timeZone,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit'
    }).format(now);
  } catch {
    return now.toISOString().slice(0, 10);
  }
}

function capFromEnv(env = process.env) {
  const raw = env.OXY_DAILY_SPEND_CAP_USD;
  if (raw === undefined || raw === '') return DEFAULT_CAP_USD;
  const value = Number(raw);
  return Number.isFinite(value) && value >= 0 ? value : DEFAULT_CAP_USD;
}

function createSpendCap({
  capUsd = DEFAULT_CAP_USD,
  spikeUsd = DEFAULT_SPIKE_USD,
  timeZone = 'Europe/London',
  now = () => new Date(),
  logger = console
} = {}) {
  const spent = new Map();

  function key(userId, at) {
    return `${userId}|${dayKey(at, timeZone)}`;
  }

  function status(userId, at = now()) {
    const used = spent.get(key(userId, at)) || 0;
    return {
      used,
      cap: capUsd,
      blocked: capUsd > 0 && used >= capUsd - 1e-9
    };
  }

  function charge(userId, usd, at = now()) {
    const amount = Number(usd);
    if (!userId || !Number.isFinite(amount) || amount <= 0) return status(userId, at);
    const id = key(userId, at);
    const next = (spent.get(id) || 0) + amount;
    spent.set(id, next);
    const crossed = capUsd > 0 && next >= capUsd - 1e-9 && next - amount < capUsd - 1e-9;
    if (amount >= spikeUsd || crossed) {
      logger.warn?.(
        `[spend] user=${userId} day=${id.split('|')[1]} added=$${amount.toFixed(4)} total=$${next.toFixed(4)} cap=$${capUsd}`
      );
    }
    return { ...status(userId, at), added: amount };
  }

  return { status, charge };
}

const shared = createSpendCap({
  capUsd: capFromEnv(),
  spikeUsd: Number(process.env.OXY_SPEND_SPIKE_USD || DEFAULT_SPIKE_USD),
  timeZone: process.env.TIMEZONE || 'Europe/London'
});

function spendCapError() {
  const error = new Error(USER_MESSAGE);
  error.code = 'spend_cap';
  return error;
}

function assertAllowed(userId) {
  if (!userId) return;
  if (shared.status(userId).blocked) throw spendCapError();
}

module.exports = {
  USER_MESSAGE,
  DEFAULT_CAP_USD,
  capFromEnv,
  createSpendCap,
  status: (userId, at) => shared.status(userId, at),
  charge: (userId, usd, at) => shared.charge(userId, usd, at),
  assertAllowed,
  spendCapError
};
