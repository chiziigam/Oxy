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

test('a failed TTS clip cannot become an unhandled rejection', async () => {
  const { createSentenceTtsStreamer } = require('../../api/index');
  const unhandled = [];
  const onUnhandled = (reason) => unhandled.push(reason);
  process.on('unhandledRejection', onUnhandled);
  try {
    const streamer = createSentenceTtsStreamer({
      voiceName: 'test',
      sse: () => {},
      speakStream: async function* () { throw new Error('tts down'); },
    });
    streamer.ingest('Hello there. This is a second sentence.');
    await assert.rejects(streamer.waitForAll(), /tts down/);
    await new Promise((resolve) => setTimeout(resolve, 20));
    assert.deepEqual(unhandled, []);
  } finally {
    process.off('unhandledRejection', onUnhandled);
  }
});

test('the Microsoft OAuth browser redirect reaches its callback instead of a 401', async () => {
  const http = require('node:http');
  const app = require('../../api/index');
  const server = http.createServer(app);
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  try {
    const { port } = server.address();
    const res = await fetch(`http://127.0.0.1:${port}/auth/microsoft/callback?state=bogus&code=x`);
    assert.equal(res.status, 400, 'a forged state must be rejected by the handler, not by the session gate');
  } finally {
    server.close();
  }
});

test('the mailer reports its no-provider mode instead of pretending to send', async () => {
  const previous = process.env.RESEND_API_KEY;
  delete process.env.RESEND_API_KEY;
  try {
    const { sendEmail } = require('../../api/services/email');
    const result = await sendEmail({ to: 'a@example.com', subject: 'Hello', text: 'Body' });
    assert.equal(result.dev, true);
    assert.equal(Boolean(result.ok) && result.dev !== true, false, 'a no-op must not count as a send');
  } finally {
    if (previous === undefined) delete process.env.RESEND_API_KEY;
    else process.env.RESEND_API_KEY = previous;
  }
});

test('a new chat can close its browser session, and only its own', async () => {
  const http = require('node:http');
  const { createSessionToken } = require('../../auth');
  const app = require('../../api/index');
  const server = http.createServer(app);
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  try {
    const { port } = server.address();
    const auth = { Authorization: `Bearer ${createSessionToken('u1')}` };
    const own = await fetch(`http://127.0.0.1:${port}/browser-session/u1/close`, { method: 'POST', headers: auth });
    assert.equal(own.status, 200);
    assert.deepEqual(await own.json(), { closed: true });
    const other = await fetch(`http://127.0.0.1:${port}/browser-session/u2/close`, { method: 'POST', headers: auth });
    assert.equal(other.status, 403);
  } finally {
    server.close();
  }
});

test('a hosting platform tenant is its own site, not the whole platform', () => {
  const { registrableSite } = require('../../api/lib/site');
  assert.equal(registrableSite('alice.github.io'), 'alice.github.io');
  assert.equal(registrableSite('www.alice.github.io'), 'alice.github.io');
  assert.equal(registrableSite('my-shop.vercel.app'), 'my-shop.vercel.app');
  assert.equal(registrableSite('shop.co.uk'), 'shop.co.uk');
  assert.equal(registrableSite('www.johnlewis.com'), 'johnlewis.com');
});

test('changing where notification email goes waits for approval', () => {
  const { getActionContract } = require('../../api/action-contracts');
  const contract = getActionContract('set_notification_preference');
  assert.equal(contract.reviewWhen({ email_to: 'somewhere@example.com' }), true);
  assert.equal(contract.reviewWhen({ channel: 'email' }), false);
  assert.equal(contract.reviewWhen({ category: 'watch', channel: 'telegram' }), false);
});

test('test-mode inventory is not described as a real, sellable fare', () => {
  const { formatTravelResults } = require('../../api/services/travel-search');
  const text = formatTravelResults('flights', [{
    kind: 'flight', airline: 'Duffel Airways', price: 100, currency: 'GBP',
    priceBasis: 'return', priceIsTotal: true, passengers: 1, inventory: true,
    source: 'Duffel (test mode — fictional inventory)',
    caveat: 'Sandbox data from Duffel Airways, not a real fare.',
    dateMatch: 'exact', matchesRequestedDates: true
  }], { searched: 'London to Paris' });
  assert.doesNotMatch(text, /real, sellable/i);
  assert.match(text, /example data|test-mode/i);
});

test('a missing user id never selects a shared browser sandbox', () => {
  const previous = {
    backend: process.env.OXY_BROWSER_BACKEND,
    key: process.env.E2B_API_KEY,
    users: process.env.OXY_BROWSER_SANDBOX_USERS,
  };
  process.env.OXY_BROWSER_BACKEND = 'e2b';
  process.env.E2B_API_KEY = 'test-key';
  delete process.env.OXY_BROWSER_SANDBOX_USERS;
  try {
    const { isEnabled } = require('../../api/services/browser-sandbox');
    assert.equal(isEnabled(undefined), false);
    assert.equal(isEnabled('u1'), true);
    process.env.OXY_BROWSER_SANDBOX_USERS = 'u2';
    assert.equal(isEnabled('u1'), false);
    assert.equal(isEnabled('u2'), true);
  } finally {
    for (const [name, value] of [
      ['OXY_BROWSER_BACKEND', previous.backend],
      ['E2B_API_KEY', previous.key],
      ['OXY_BROWSER_SANDBOX_USERS', previous.users],
    ]) {
      if (value === undefined) delete process.env[name];
      else process.env[name] = value;
    }
  }
});
