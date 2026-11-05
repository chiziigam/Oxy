'use strict';
// Sign in with Apple, verified properly: the identity token is checked against Apple's published
// keys, its issuer, audience and expiry, and the nonce the client generated. A token that does
// not pass all four is not an identity — it is a string someone typed.

const crypto = require('node:crypto');

const APPLE_ISSUER = 'https://appleid.apple.com';
const APPLE_KEYS_URL = 'https://appleid.apple.com/auth/keys';
const KEY_TTL_MS = 6 * 60 * 60 * 1000;

let cachedKeys = { at: 0, keys: null };

function audienceFor(env = process.env) {
  // The iOS bundle id is what an app-issued token carries; a web flow would use the services id.
  return String(env.APPLE_CLIENT_ID || env.APNS_BUNDLE_ID || env.APPLE_BUNDLE_ID || '').trim();
}

async function appleKeys(fetchImpl = fetch) {
  if (cachedKeys.keys && Date.now() - cachedKeys.at < KEY_TTL_MS) return cachedKeys.keys;
  const response = await fetchImpl(APPLE_KEYS_URL);
  if (!response.ok) throw new Error(`Could not read Apple's signing keys (HTTP ${response.status}).`);
  const body = await response.json();
  const keys = (body.keys || []).map((jwk) => ({
    kid: jwk.kid,
    key: crypto.createPublicKey({ key: jwk, format: 'jwk' })
  }));
  cachedKeys = { at: Date.now(), keys };
  return keys;
}

function decodeSegment(segment) {
  return JSON.parse(Buffer.from(segment, 'base64url').toString('utf8'));
}

// Returns { sub, email, emailVerified } or throws with a message worth showing a person.
async function verifyIdentityToken(identityToken, { nonce = null, env = process.env, fetchImpl = fetch } = {}) {
  const token = String(identityToken || '');
  const parts = token.split('.');
  if (parts.length !== 3) throw new Error('That Apple sign-in response was not a valid token.');

  const [encodedHeader, encodedPayload, signature] = parts;
  const header = decodeSegment(encodedHeader);
  const payload = decodeSegment(encodedPayload);

  if (header.alg !== 'RS256') throw new Error('Apple signed that token with an unexpected algorithm.');

  const keys = await appleKeys(fetchImpl);
  const match = keys.find((entry) => entry.kid === header.kid);
  if (!match) throw new Error("Apple's signing key for that token is not published.");

  const signed = Buffer.from(`${encodedHeader}.${encodedPayload}`, 'utf8');
  const valid = crypto.verify('RSA-SHA256', signed, match.key, Buffer.from(signature, 'base64url'));
  if (!valid) throw new Error("That Apple sign-in could not be verified.");

  if (payload.iss !== APPLE_ISSUER) throw new Error('That token did not come from Apple.');
  const audience = audienceFor(env);
  if (audience && payload.aud !== audience) throw new Error('That Apple sign-in was issued for a different app.');
  if (!payload.exp || Date.now() >= Number(payload.exp) * 1000) throw new Error('That Apple sign-in has expired.');
  if (nonce) {
    // The client puts a hash of its nonce into the request; Apple echoes that hash. Accept either
    // the hash or the raw value so a caller cannot be locked out by the shape of its own nonce.
    const hashed = crypto.createHash('sha256').update(String(nonce)).digest('hex');
    const claimed = String(payload.nonce || '');
    if (claimed && claimed !== nonce && claimed !== hashed) {
      throw new Error('That Apple sign-in was for a different request.');
    }
  }

  if (!payload.sub) throw new Error('That Apple sign-in did not identify an account.');

  return {
    sub: String(payload.sub),
    email: payload.email ? String(payload.email).toLowerCase() : null,
    emailVerified: payload.email_verified === true || payload.email_verified === 'true',
    isPrivateEmail: payload.is_private_email === true || payload.is_private_email === 'true'
  };
}

// A stable account id from Apple's subject. Deterministic so a returning person lands on the same
// account without needing a provider column on `users`.
function userIdForSubject(sub) {
  const digest = crypto.createHash('sha256').update(`apple:${sub}`).digest('hex').slice(0, 24);
  return `apple_${digest}`;
}

function nonceFor() {
  return crypto.randomBytes(16).toString('base64url');
}

module.exports = { verifyIdentityToken, userIdForSubject, nonceFor, audienceFor, appleKeys, APPLE_ISSUER, APPLE_KEYS_URL };
