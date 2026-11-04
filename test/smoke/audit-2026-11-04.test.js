const assert = require('node:assert/strict');
const test = require('node:test');
const crypto = require('node:crypto');

// JOSE ES256 signs with the raw IEEE P1363 r‖s pair (64 bytes for P-256). Node's default is
// DER, which Apple rejects as InvalidProviderToken, so this pins the encoding rather than
// trusting the call site.
test('the APNs provider token uses a JOSE ES256 signature, not DER', () => {
  const { privateKey } = crypto.generateKeyPairSync('ec', { namedCurve: 'P-256' });
  const key = privateKey.export({ type: 'pkcs8', format: 'pem' });
  const previous = {
    keyId: process.env.APNS_KEY_ID,
    teamId: process.env.APNS_TEAM_ID,
    key: process.env.APNS_PRIVATE_KEY,
  };
  process.env.APNS_KEY_ID = 'KEYID12345';
  process.env.APNS_TEAM_ID = 'TEAMID1234';
  process.env.APNS_PRIVATE_KEY = key;

  try {
    const { buildApnsAuthToken } = require('../../api/index');
    const token = buildApnsAuthToken();
    const [header, payload, signature] = token.split('.');
    assert.equal(JSON.parse(Buffer.from(header, 'base64url')).alg, 'ES256');
    assert.equal(JSON.parse(Buffer.from(payload, 'base64url')).iss, 'TEAMID1234');
    assert.equal(Buffer.from(signature, 'base64url').length, 64);
  } finally {
    for (const [name, value] of [
      ['APNS_KEY_ID', previous.keyId],
      ['APNS_TEAM_ID', previous.teamId],
      ['APNS_PRIVATE_KEY', previous.key],
    ]) {
      if (value === undefined) delete process.env[name];
      else process.env[name] = value;
    }
  }
});
