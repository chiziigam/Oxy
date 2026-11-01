'use strict';

// Limits for routes that spend money or call a paid lookup and previously had none.
// In memory, same as the other limiters: this deploy runs one machine.

function createLimiter({ max, windowMs, now = () => Date.now() } = {}) {
  const hits = new Map();
  return function costRouteLimit(req, res, next) {
    const key = req.auth?.userId || req.params?.userId || req.body?.userId || req.ip || 'unknown';
    const at = now();
    const recent = (hits.get(key) || []).filter(t => at - t < windowMs);
    if (recent.length >= max) {
      res.status(429).json({ error: 'Too many requests. Try again in a moment.' });
      return;
    }
    recent.push(at);
    hits.set(key, recent);
    next();
  };
}

const MINUTE = 60 * 1000;
const ttsPreviewLimit = createLimiter({ max: 8, windowMs: MINUTE });
const geocodeLimit = createLimiter({ max: 20, windowMs: MINUTE });
const homeAddressLimit = createLimiter({ max: 20, windowMs: MINUTE });
const proactiveRunLimit = createLimiter({ max: 4, windowMs: 60 * MINUTE });

module.exports = {
  createLimiter,
  ttsPreviewLimit,
  geocodeLimit,
  homeAddressLimit,
  proactiveRunLimit
};
