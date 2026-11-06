const assert = require('node:assert/strict');
const test = require('node:test');

const { streamBrain } = require('../../api/services/brain-provider');

function sseResponse(events) {
  const body = events.map(ev => `data: ${JSON.stringify(ev)}\n\n`).join('');
  return new Response(body, { status: 200, headers: { 'Content-Type': 'text/event-stream' } });
}

async function collect(stream) {
  const chunks = [];
  for await (const chunk of stream) chunks.push(chunk);
  return chunks;
}

const reply = [
  { type: 'response.reasoning_summary_part.added' },
  { type: 'response.reasoning_summary_text.delta', delta: '**Checking tomorrow' },
  { type: 'response.reasoning_summary_text.delta', delta: ' on the calendar**\n\nI should look at what is booked.' },
  { type: 'response.reasoning_summary_part.added' },
  { type: 'response.reasoning_summary_text.delta', delta: '**Working out a wake-up time**\n\nMore thinking.' },
  { type: 'response.output_text.delta', delta: 'Set it for 8:00.' },
  { type: 'response.completed', response: { model: 'gpt-6-luna', usage: { input_tokens: 1, output_tokens: 1 } } }
];

async function withFetch(handler, run) {
  const originalFetch = global.fetch;
  const originalKey = process.env.OPENAI_API_KEY;
  const originalSummary = process.env.OXY_REASONING_SUMMARY;
  process.env.OPENAI_API_KEY = 'test-key';
  delete process.env.OXY_REASONING_SUMMARY;
  global.fetch = handler;
  try { return await run(); } finally {
    global.fetch = originalFetch;
    if (originalKey === undefined) delete process.env.OPENAI_API_KEY; else process.env.OPENAI_API_KEY = originalKey;
    if (originalSummary !== undefined) process.env.OXY_REASONING_SUMMARY = originalSummary;
  }
}

const request = { provider: 'openai', model: 'gpt-6-luna', contents: [{ role: 'user', parts: [{ text: 'when do I wake up' }] }], config: {} };

test('each stretch of thinking comes through once, as its title, apart from the answer text', async () => {
  const sent = [];
  const chunks = await withFetch(async (_url, init) => { sent.push(JSON.parse(init.body)); return sseResponse(reply); },
    async () => collect(streamBrain(request)));
  assert.equal(sent[0].reasoning.summary, 'auto');
  assert.deepEqual(chunks.filter(c => c.thought).map(c => c.thought), ['Checking tomorrow on the calendar', 'Working out a wake-up time']);
  assert.equal(chunks.filter(c => c.text).map(c => c.text).join(''), 'Set it for 8:00.');
});

test('an account that cannot return thinking summaries still gets its answer', async () => {
  const sent = [];
  let calls = 0;
  const chunks = await withFetch(async (_url, init) => {
    calls += 1;
    sent.push(JSON.parse(init.body));
    if (calls === 1) return new Response('Your organization must be verified to generate reasoning summaries', { status: 400 });
    return sseResponse(reply.filter(ev => !String(ev.type).includes('reasoning_summary')));
  }, async () => collect(streamBrain(request)));
  assert.equal(calls, 2);
  assert.equal(sent[1].reasoning.summary, undefined);
  assert.equal(chunks.filter(c => c.thought).length, 0);
  assert.equal(chunks.filter(c => c.text).map(c => c.text).join(''), 'Set it for 8:00.');
});

test('an unrelated provider error is not retried', async () => {
  let calls = 0;
  await withFetch(async () => { calls += 1; return new Response('rate limited', { status: 429 }); },
    async () => assert.rejects(() => collect(streamBrain(request)), /429/));
  assert.equal(calls, 1);
});
