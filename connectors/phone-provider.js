'use strict';

// The provider seam for Adam's phone identity, so the telecom vendor is one registration away
// from being swapped. Twilio is the current default, being the only one confirmed to sell UK
// mobile numbers without UK proof-of-address.
//
// The asymmetry that matters: provisioning follows the active provider, sending follows the
// provider that issued the number being sent from. Otherwise switching vendors orphans every
// number already in the field — which is why the handle's provider is written from the
// provisioning result and read back on every send.

const providers = new Map();

// An adapter must supply all four:
//   provisionPhoneNumber(userId) -> { phoneNumber, providerRef }
//   sendSms({ from, to, body })  -> { providerMessageId }
//   parseInboundSms(payload)     -> normalized event | null
//   inboundAck()                 -> { contentType, body }
function registerProvider(name, implementation) {
  providers.set(String(name).trim().toLowerCase(), implementation);
}

function activeProviderName() {
  return String(process.env.MILLIE_PHONE_PROVIDER || 'twilio').trim().toLowerCase();
}

function getProvider(name) {
  const key = String(name || activeProviderName()).trim().toLowerCase();
  const implementation = providers.get(key);
  if (!implementation) {
    throw new Error(
      `Unknown phone provider "${key}". Set MILLIE_PHONE_PROVIDER to one of: ${[...providers.keys()].join(', ')}.`
    );
  }
  return implementation;
}

async function provisionPhoneNumber(userId) {
  const name = activeProviderName();
  const result = await getProvider(name).provisionPhoneNumber(userId);
  // Stamped so the handle row records who owns this number, not who happens to be
  // configured at the moment it is later used.
  return { ...result, provider: name };
}

async function sendSms({ from, to, body, provider }) {
  return getProvider(provider).sendSms({ from, to, body });
}

function parseInboundSms(payload, provider) {
  return getProvider(provider).parseInboundSms(payload);
}

function inboundAck(provider) {
  return getProvider(provider).inboundAck();
}

// Providers that sign their webhooks supply verifyInbound(req); the route calls it when present.
function verifyInbound(req, provider) {
  const implementation = getProvider(provider);
  return typeof implementation.verifyInbound === 'function' ? implementation.verifyInbound(req) : null;
}

// --- Built-in adapters ---------------------------------------------------------
// Twilio's connector keeps its own export names; the adapter shape is applied here so
// the existing module (and its tests) stay untouched.

const twilio = require('./adam-sms-twilio');

registerProvider('twilio', {
  provisionPhoneNumber: (userId) => twilio.provisionPhoneNumber(userId),
  sendSms: ({ from, to, body }) => twilio.sendAdamSms({ from, to, body }),
  parseInboundSms: (payload) => twilio.parseInboundSmsPayload(payload),
  // Twilio expects TwiML or an empty 200 on the inbound webhook. That is a Twilio
  // quirk, so it lives with the Twilio adapter rather than in the shared route.
  inboundAck: () => ({ contentType: 'text/xml', body: '<Response></Response>' })
});

const linq = require('./adam-imessage-linq');

registerProvider('linq', {
  provisionPhoneNumber: (userId) => linq.provisionPhoneNumber(userId),
  sendSms: ({ from, to, body }) => linq.sendMessage({ from, to, body }),
  parseInboundSms: (payload) => linq.parseInboundWebhook(payload),
  verifyInbound: (req) => linq.verifyWebhookSignature(req.rawBody || '', req.headers, process.env.LINQ_WEBHOOK_SECRET),
  // Linq retries on non-2xx, so acknowledge with an empty JSON object.
  inboundAck: () => ({ contentType: 'application/json', body: '{}' })
});

module.exports = {
  registerProvider,
  getProvider,
  activeProviderName,
  provisionPhoneNumber,
  sendSms,
  parseInboundSms,
  inboundAck,
  verifyInbound
};
