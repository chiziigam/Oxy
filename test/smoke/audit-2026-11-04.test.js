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

test('device GPS never overwrites a place the model named', async () => {
  const { createDeclaredAdapterInvoker } = require('../../api/services/declared-adapter-invoker');
  let captured = null;
  const invoke = createDeclaredAdapterInvoker({
    executeInline: async ({ input }) => { captured = input; return { success: true }; },
    dispatchConnector: async () => ({ success: true }),
  });
  const gps = { latitude: 52.4, longitude: -1.8 };

  await invoke({ adapter: { kind: 'inline' }, userId: 'u1', type: 'search_hotels', input: { location: 'Bath' }, context: { location: gps } });
  assert.equal(captured.location, 'Bath');

  await invoke({ adapter: { kind: 'inline' }, userId: 'u1', type: 'find_nearby_places', input: {}, context: { location: gps } });
  assert.deepEqual(captured.location, gps);
});

test('deleting a whole saved person waits for approval', () => {
  const { getActionContract } = require('../../api/action-contracts');
  const contract = getActionContract('forget_person_detail');
  assert.equal(contract.reviewWhen({ delete_person: true }), true);
  assert.equal(contract.reviewWhen({ delete_person: 'true' }), true);
  assert.equal(contract.reviewWhen({ person_name: 'Ben', facts: ['met at work'] }), false);
});
