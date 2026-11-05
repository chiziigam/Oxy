'use strict';
const axios = require('axios');
const crypto = require('crypto');

// Adam's iMessage line over Linq's Partner API (v3). Plain REST, no SDK, like the other connectors.
// Linq lines are issued by Linq, not bought through the API, so "provisioning" returns the line
// from LINQ_FROM_NUMBER. Sends use POST /v3/chats with that line as `from`. Inbound events are
// `message.received` webhooks signed with the Standard Webhooks scheme.

const LINQ_BASE = 'https://api.linqapp.com/api/partner';
const WEBHOOK_TOLERANCE_SECONDS = 5 * 60;

function linqKey() {
  const key = process.env.LINQ_API_KEY;
  if (!key) throw new Error('LINQ_API_KEY is not configured.');
  return key;
}

async function provisionPhoneNumber() {
  linqKey();
  const line = String(process.env.LINQ_FROM_NUMBER || '').trim();
  if (!line) throw new Error('LINQ_FROM_NUMBER is not configured. Linq issues the line; set it to the E.164 number.');
  return { phoneNumber: line, providerRef: 'linq' };
}

async function sendMessage({ from, to, body, idempotencyKey, http = axios }) {
  const key = linqKey();
  if (!from || !to || !body) throw new Error('A Linq send needs a from line, a recipient and a body.');
  const message = { parts: [{ type: 'text', value: String(body).slice(0, 10000) }] };
  if (idempotencyKey) message.idempotency_key = String(idempotencyKey).slice(0, 255);
  const response = await http.post(
    `${LINQ_BASE}/v3/chats`,
    { from, to: [to], message },
    { headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' }, timeout: 15000 }
  );
  const data = response.data || {};
  return { providerMessageId: data.chat?.message?.id || data.message?.id || data.chat?.id || null };
}

// message.received -> the shape the shared inbound route expects. Anything else (our own sends,
// delivery and read receipts, group chats) returns null and is ignored.
function parseInboundWebhook(payload) {
  const event = payload || {};
  if (event.event_type !== 'message.received') return null;
  const data = event.data || {};
  if (data.direction !== 'inbound') return null;
  if (data.chat?.is_group) return null;
  const from = String(data.sender_handle?.handle || '').trim();
  const to = String(data.chat?.owner_handle?.handle || '').trim();
  if (!from || !to) return null;
  const text = (Array.isArray(data.parts) ? data.parts : [])
    .filter(part => part?.type === 'text' && typeof part.value === 'string')
    .map(part => part.value)
    .join('\n');
  return {
    fromAddress: from,
    toAddress: to,
    subject: '',
    body: text,
    providerMessageId: data.id || event.event_id || null,
    inReplyTo: null,
    references: null
  };
}

function safeEqual(a, b) {
  const x = Buffer.from(String(a));
  const y = Buffer.from(String(b));
  return x.length === y.length && crypto.timingSafeEqual(x, y);
}

// Standard Webhooks: HMAC-SHA256 over "{webhook-id}.{webhook-timestamp}.{raw body}", keyed with the
// base64-decoded secret (minus its `whsec_` prefix). The header holds space-separated `v1,<base64>`.
function verifyWebhookSignature(rawBody, headers = {}, secret, nowMs = Date.now()) {
  if (!secret) return false;
  const get = name => headers[name] ?? headers[name.toLowerCase()];
  const id = get('webhook-id');
  const timestamp = get('webhook-timestamp');
  const signatures = get('webhook-signature');
  if (!id || !timestamp || !signatures) return false;
  const seconds = Number(timestamp);
  if (!Number.isFinite(seconds) || Math.abs(nowMs / 1000 - seconds) > WEBHOOK_TOLERANCE_SECONDS) return false;
  const key = Buffer.from(String(secret).replace(/^whsec_/, ''), 'base64');
  const expected = crypto.createHmac('sha256', key).update(`${id}.${timestamp}.${rawBody}`).digest('base64');
  return String(signatures).split(' ').some(part => {
    const [version, value] = part.split(',');
    return version === 'v1' && value && safeEqual(value, expected);
  });
}

module.exports = { provisionPhoneNumber, sendMessage, parseInboundWebhook, verifyWebhookSignature };
