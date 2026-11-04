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

test('guard mode gates writes but still lets Adam look at the page', async () => {
  const { createActionExecution } = require('../../api/services/action-execution');
  const { getActionContract } = require('../../api/action-contracts');
  const parked = [];
  const executed = [];
  const run = createActionExecution({
    invokeAdapter: async ({ type }) => { executed.push(type); return { success: true, text: 'ok' }; },
    setPendingAction: async (userId, action) => { parked.push(action.type); return { approvalId: 'ap1' }; },
    logAction: async () => {},
    resolveContract: getActionContract,
    resolveAdapter: () => ({ kind: 'inline' }),
  });

  await run('u1', [
    { type: 'get_emails', input: {} },
    { type: 'send_email', input: { to: 'a@example.com', body: 'Hello.' } },
  ], { guardMode: true, userMessage: 'check my mail and email a' });

  assert.deepEqual(executed, ['get_emails']);
  assert.deepEqual(parked, ['send_email']);
});

test('an unreadable chat setting keeps approval mode on; a missing row keeps the default', async () => {
  const { getChatSettings } = require('../../api/services/chat-settings');
  const client = (error) => ({
    from: () => ({ select: () => ({ eq: () => ({ single: async () => ({ data: null, error }) }) }) }),
  });
  const failed = await getChatSettings(client({ code: 'XX000', message: 'db down' }), 'u1');
  assert.equal(failed.guardMode, true);
  assert.equal(failed.unavailable, true);
  const missing = await getChatSettings(client({ code: 'PGRST116', message: 'no rows' }), 'u1');
  assert.equal(missing.guardMode, false);
});

test('string "false" on a yes/no parameter is read as false, not as truthy text', () => {
  const { validateActionWithContract, actionToFunctionDeclaration, getActionContract } = require('../../api/action-contracts');

  const action = { type: 'browser_act', input: { action: 'type', submit: 'false' } };
  validateActionWithContract(action, 'type my name into the form');
  assert.equal(action.input.submit, false);

  const clean = { type: 'clean_inbox', input: { unsubscribe_senders: 'false' } };
  validateActionWithContract(clean, 'clean my inbox but do not unsubscribe me');
  assert.equal(clean.input.unsubscribe_senders, false);

  const declaration = actionToFunctionDeclaration('browser_act', getActionContract('browser_act'));
  assert.equal(declaration.parameters.properties.submit.type, 'BOOLEAN');
  assert.equal(declaration.parameters.properties.action.type, 'STRING');
});

test('browser_act refuses a control that would charge', () => {
  const { refusePaymentCommit } = require('../../api/services/browser-environment');
  for (const label of ['Place order', 'Pay now', 'Buy now', 'Complete purchase', 'Confirm and pay']) {
    assert.throws(() => refusePaymentCommit(label), /transaction_prepare/, label);
  }
  for (const label of ['Add to basket', 'Continue to payment', 'Apply', 'Sign in']) {
    assert.doesNotThrow(() => refusePaymentCommit(label), label);
  }
});

test('deploy refuses a dirty tree or a branch that is not main', () => {
  const { assertDeployable } = require('../../scripts/deploy-fly');
  assert.throws(() => assertDeployable({ branch: 'HEAD', status: '' }), /detached HEAD/);
  assert.throws(() => assertDeployable({ branch: 'feature', status: '' }), /Refusing to deploy from "feature"/);
  assert.doesNotThrow(() => assertDeployable({ branch: 'feature', status: '', env: { OXY_DEPLOY_BRANCH: '1' } }));
  assert.throws(() => assertDeployable({ branch: 'main', status: ' M api/index.js' }), /dirty working tree/);
  assert.doesNotThrow(() => assertDeployable({ branch: 'main', status: ' M api/index.js', env: { OXY_DEPLOY_DIRTY: '1' } }));
  assert.doesNotThrow(() => assertDeployable({ branch: 'main', status: '' }));
});

test('retention runs daily wherever the heartbeat is on', () => {
  const { retentionSettings } = require('../../api/services/heartbeat');
  const on = retentionSettings({ OXY_HEARTBEAT: 'on' });
  assert.equal(on.enabled, true);
  assert.equal(on.intervalMs, 24 * 60 * 60 * 1000);
  assert.equal(retentionSettings({}).enabled, false);
});

test('local device data is excluded from the production image', () => {
  const ignore = require('node:fs').readFileSync(require('node:path').join(__dirname, '../../.dockerignore'), 'utf8');
  assert.match(ignore, /^data$/m);
});
