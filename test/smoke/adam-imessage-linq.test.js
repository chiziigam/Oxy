const assert = require('node:assert/strict');
const test = require('node:test');
const crypto = require('node:crypto');
const http = require('node:http');

const linq = require('../../connectors/adam-imessage-linq');
const { sendSms, parseInboundSms, inboundAck, verifyInbound, provisionPhoneNumber } = require('../../connectors/phone-provider');

function withEnv(vars, fn) {
  const old = {};
  for (const [k, v] of Object.entries(vars)) { old[k] = process.env[k]; if (v === undefined) delete process.env[k]; else process.env[k] = v; }
  const restore = () => { for (const [k, v] of Object.entries(old)) { if (v === undefined) delete process.env[k]; else process.env[k] = v; } };
  try { const r = fn(); if (r && typeof r.then === 'function') return r.finally(restore); restore(); return r; } catch (e) { restore(); throw e; }
}

const SECRET_RAW = crypto.randomBytes(24);
const SECRET = `whsec_${SECRET_RAW.toString('base64')}`;

function sign(body, { id = 'msg_1', timestamp = Math.floor(Date.now() / 1000), key = SECRET_RAW } = {}) {
  const sig = crypto.createHmac('sha256', key).update(`${id}.${timestamp}.${body}`).digest('base64');
  return { 'webhook-id': id, 'webhook-timestamp': String(timestamp), 'webhook-signature': `v1,${sig}` };
}

const inboundEvent = (overrides = {}) => ({
  api_version: 'v3', webhook_version: '2026-02-03', event_type: 'message.received', event_id: 'evt-1',
  data: {
    id: 'm-1', direction: 'inbound',
    chat: { id: 'c-1', is_group: false, owner_handle: { handle: '+12025551234', is_me: true } },
    sender_handle: { handle: '+12025559876', is_me: false },
    parts: [{ type: 'text', value: 'Hello' }, { type: 'media', url: 'https://x/y.png' }, { type: 'text', value: 'again' }],
    ...overrides
  }
});

test('sendMessage posts to /v3/chats with bearer auth, the line as from, and a text part', async () => {
  const calls = [];
  const fakeHttp = { post: async (url, body, opts) => { calls.push({ url, body, opts }); return { data: { chat: { id: 'chat-9', message: { id: 'msg-9' } } } }; } };
  const result = await withEnv({ LINQ_API_KEY: 'k-test' }, () =>
    linq.sendMessage({ from: '+12025551234', to: '+12025559876', body: 'hi', idempotencyKey: 'abc', http: fakeHttp }));
  assert.equal(calls[0].url, 'https://api.linqapp.com/api/partner/v3/chats');
  assert.equal(calls[0].opts.headers.Authorization, 'Bearer k-test');
  assert.deepEqual(calls[0].body, {
    from: '+12025551234', to: ['+12025559876'],
    message: { parts: [{ type: 'text', value: 'hi' }], idempotency_key: 'abc' }
  });
  assert.equal(result.providerMessageId, 'msg-9');
});

test('sendMessage refuses without a key or without a body', async () => {
  await withEnv({ LINQ_API_KEY: undefined }, () => assert.rejects(linq.sendMessage({ from: 'a', to: 'b', body: 'c' }), /LINQ_API_KEY/));
  await withEnv({ LINQ_API_KEY: 'k' }, () => assert.rejects(linq.sendMessage({ from: 'a', to: 'b', body: '' }), /needs a from line/));
});

test('provisioning returns the configured Linq line and fails loudly when it is missing', async () => {
  const ok = await withEnv({ LINQ_API_KEY: 'k', LINQ_FROM_NUMBER: ' +12025551234 ' }, () => linq.provisionPhoneNumber());
  assert.deepEqual(ok, { phoneNumber: '+12025551234', providerRef: 'linq' });
  await withEnv({ LINQ_API_KEY: 'k', LINQ_FROM_NUMBER: undefined }, () => assert.rejects(linq.provisionPhoneNumber(), /LINQ_FROM_NUMBER/));
});

test('parseInboundWebhook maps message.received to the shared inbound shape, text parts only', () => {
  const parsed = linq.parseInboundWebhook(inboundEvent());
  assert.equal(parsed.fromAddress, '+12025559876');
  assert.equal(parsed.toAddress, '+12025551234');
  assert.equal(parsed.body, 'Hello\nagain');
  assert.equal(parsed.providerMessageId, 'm-1');
});

test('parseInboundWebhook ignores other events, outbound messages and group chats', () => {
  assert.equal(linq.parseInboundWebhook({ ...inboundEvent(), event_type: 'message.delivered' }), null);
  assert.equal(linq.parseInboundWebhook(inboundEvent({ direction: 'outbound' })), null);
  assert.equal(linq.parseInboundWebhook(inboundEvent({ chat: { is_group: true, owner_handle: { handle: '+1' } } })), null);
  assert.equal(linq.parseInboundWebhook(null), null);
});

test('verifyWebhookSignature accepts a correct signature and rejects tampering, wrong secret and stale timestamps', () => {
  const body = JSON.stringify(inboundEvent());
  assert.equal(linq.verifyWebhookSignature(body, sign(body), SECRET), true);
  assert.equal(linq.verifyWebhookSignature(body + ' ', sign(body), SECRET), false);
  assert.equal(linq.verifyWebhookSignature(body, sign(body, { key: crypto.randomBytes(24) }), SECRET), false);
  const old = Math.floor(Date.now() / 1000) - 600;
  assert.equal(linq.verifyWebhookSignature(body, sign(body, { timestamp: old }), SECRET), false);
  assert.equal(linq.verifyWebhookSignature(body, {}, SECRET), false);
  assert.equal(linq.verifyWebhookSignature(body, sign(body), ''), false);
});

test('verifyWebhookSignature accepts any of several space-separated signatures', () => {
  const body = '{}';
  const headers = sign(body);
  headers['webhook-signature'] = `v1,AAAA ${headers['webhook-signature']}`;
  assert.equal(linq.verifyWebhookSignature(body, headers, SECRET), true);
});

test('the phone-provider seam routes to Linq by name', async () => {
  const parsed = parseInboundSms(inboundEvent(), 'linq');
  assert.equal(parsed.fromAddress, '+12025559876');
  assert.equal(inboundAck('linq').body, '{}');
  const body = JSON.stringify(inboundEvent());
  const req = { rawBody: body, headers: sign(body) };
  assert.equal(withEnv({ LINQ_WEBHOOK_SECRET: SECRET }, () => verifyInbound(req, 'linq')), true);
  assert.equal(withEnv({ LINQ_WEBHOOK_SECRET: undefined }, () => verifyInbound(req, 'linq')), false);
  const prov = await withEnv({ MILLIE_PHONE_PROVIDER: 'linq', LINQ_API_KEY: 'k', LINQ_FROM_NUMBER: '+12025551234' }, () => provisionPhoneNumber('u'));
  assert.equal(prov.provider, 'linq');
  assert.equal(typeof sendSms, 'function');
});

test('POST /webhooks/millie-sms/linq acks 200 for a signed event and for an unsigned one', async () => {
  const app = require('../../api/index');
  const server = app.listen(0);
  const post = (body, headers) => new Promise((resolve, reject) => {
    const req = http.request({ method: 'POST', hostname: '127.0.0.1', port: server.address().port, path: '/webhooks/millie-sms/linq',
      headers: { 'Content-Type': 'application/json', ...headers } },
      res => { let d = ''; res.on('data', c => { d += c; }); res.on('end', () => resolve({ status: res.statusCode, data: d })); });
    req.on('error', reject); req.write(body); req.end();
  });
  try {
    await withEnv({ LINQ_WEBHOOK_SECRET: SECRET }, async () => {
      const body = JSON.stringify(inboundEvent());
      const signed = await post(body, sign(body));
      assert.equal(signed.status, 200);
      assert.equal(signed.data, '{}');
      const unsigned = await post(body, {});
      assert.equal(unsigned.status, 200);
    });
  } finally {
    server.close();
  }
});
