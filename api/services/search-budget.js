'use strict';

// Remembers recent search answers so a repeated search is free. It does not limit how many
// searches Adam can run.

// Long enough to cover one question, short enough that asking again later gets fresh results.
const DEFAULT_TTL_MS = 3 * 60 * 1000;

function normaliseQuery(query) {
  return String(query || '').toLowerCase().replace(/[^\p{L}\p{N}\s]/gu, ' ').replace(/\s+/g, ' ').trim();
}

function createSearchBudget({ now = () => Date.now(), ttlMs = DEFAULT_TTL_MS } = {}) {
  const answers = new Map(); // user|query -> { text, at }

  function sweep() {
    const cutoff = now() - ttlMs;
    for (const [key, entry] of answers) if (entry.at < cutoff) answers.delete(key);
  }

  return {
    // A recent identical search: the answer, at no cost.
    cached(userId, query) {
      sweep();
      const entry = answers.get(`${userId}|${normaliseQuery(query)}`);
      return entry ? entry.text : null;
    },
    record(userId, query, text) {
      if (text) answers.set(`${userId}|${normaliseQuery(query)}`, { text, at: now() });
    },
  };
}

module.exports = { createSearchBudget, normaliseQuery };
