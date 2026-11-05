'use strict';
// Sign in with Apple is only as trustworthy as the token check. These pose a real RSA key and a
// JWKS document shaped like Apple's, so every rejection below is a token a server would have
// accepted if it merely decoded the payload.

const crypto = require('node:crypto');
const assert = require('node:assert/strict');
const test = require('node:test');

const apple = require('../../api/services/apple-auth');

const { privateKey, publicKey } = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });
const jwk = { ...publicKey.export({ format: 'jwk' }), kid: 'test-kid', alg: 'RS256', use: 'sig' };
const fakeFetch = async () => ({ ok: true, json: async () => ({ keys: [jwk] }) });

function sign(payloadOverrides = {}, headerOverrides = {}) {
  const header = { alg: 'RS256', kid: 'test-kid', typ: 'JWT', ...headerOverrides };
  const payload = {
    iss: 'https://appleid.apple.com',
    aud: 'ai.oxy.app',
    exp: Math.floor(Date.now() / 1000) + 600,
    sub: '000123.abc.01',
    email: 'person@privaterelay.appleid.com',
    email_verified: 'true',
    is_private_email: 'true',
    ...payloadOverrides
  };
  const encodedHeader = Buffer.from(JSON.stringify(header)).toString('base64url');
  const encodedPayload = Buffer.from(JSON.stringify(payload)).toString('base64url');
  const signature = crypto.sign('RSA-SHA256', Buffer.from(`${encodedHeader}.${encodedPayload}`), privateKey).toString('base64url');
  return { token: `${encodedHeader}.${encodedPayload}.${signature}`, payload };
}

const env = { APPLE_CLIENT_ID: 'ai.oxy.app' };

test('a genuine token yields the subject and the private-relay email', async () => {
  const { token } = sign();
  const identity = await apple.verifyIdentityToken(token, { env, fetchImpl: fakeFetch });
  assert.equal(identity.sub, '000123.abc.01');
  assert.equal(identity.email, 'person@privaterelay.appleid.com');
  assert.equal(identity.emailVerified, true);
  assert.equal(identity.isPrivateEmail, true);
});

test('a token signed by anyone else is refused', async () => {
  const other = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });
  const header = Buffer.from(JSON.stringify({ alg: 'RS256', kid: 'test-kid' })).toString('base64url');
  const payload = Buffer.from(JSON.stringify({ iss: 'https://appleid.apple.com', aud: 'ai.oxy.app', exp: Math.floor(Date.now() / 1000) + 600, sub: 'x' })).toString('base64url');
  const signature = crypto.sign('RSA-SHA256', Buffer.from(`${header}.${payload}`), other.privateKey).toString('base64url');
  await assert.rejects(
    () => apple.verifyIdentityToken(`${header}.${payload}.${signature}`, { env, fetchImpl: fakeFetch }),
    /could not be verified/i
  );
});

test('the wrong issuer, audience or an expired token are all refused', async () => {
  await assert.rejects(() => apple.verifyIdentityToken(sign({ iss: 'https://evil.example' }).token, { env, fetchImpl: fakeFetch }), /did not come from Apple/i);
  await assert.rejects(() => apple.verifyIdentityToken(sign({ aud: 'com.someone.else' }).token, { env, fetchImpl: fakeFetch }), /different app/i);
  await assert.rejects(() => apple.verifyIdentityToken(sign({ exp: Math.floor(Date.now() / 1000) - 60 }).token, { env, fetchImpl: fakeFetch }), /expired/i);
});

test('a token for a different request is refused when a nonce was expected', async () => {
  const { token } = sign({ nonce: 'theirs' });
  await assert.rejects(
    () => apple.verifyIdentityToken(token, { env, nonce: 'ours', fetchImpl: fakeFetch }),
    /different request/i
  );
});

test('a token that is not even JSON is refused with a readable message', async () => {
  await assert.rejects(
    () => apple.verifyIdentityToken('a.b.c', { env, fetchImpl: fakeFetch }),
    /not a valid token/i
  );
});

test('a token with no subject is refused', async () => {
  const { token } = sign({ sub: '' });
  await assert.rejects(() => apple.verifyIdentityToken(token, { env, fetchImpl: fakeFetch }), /did not identify/i);
});

test('the account id derived from a subject is stable and not reversible', () => {
  const first = apple.userIdForSubject('000123.abc.01');
  const second = apple.userIdForSubject('000123.abc.01');
  assert.equal(first, second);
  assert.match(first, /^apple_[0-9a-f]{24}$/);
  assert.notEqual(first, apple.userIdForSubject('000123.abc.02'));
  assert.ok(!first.includes('000123'));
});
