const assert = require('node:assert/strict');
const test = require('node:test');

process.env.GEMINI_API_KEY = process.env.GEMINI_API_KEY || 'test-key';

const { extractToolCalls } = require('../../api/services/agent-orchestrator');

test('extractToolCalls does not double-count a call present in both parts and resp.functionCalls', () => {
  // Shape seen live: @google/genai's resp.functionCalls is a derived view over the same
  // candidates[0].content.parts array, not an independent second call.
  const resp = {
    candidates: [{ content: { parts: [{ functionCall: { name: 'browser_open', args: { url: 'https://shop.example' } } }] } }],
    functionCalls: [{ name: 'browser_open', args: { url: 'https://shop.example' } }]
  };
  const calls = extractToolCalls(resp);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].name, 'browser_open');
  assert.deepEqual(calls[0].args, { url: 'https://shop.example' });
});

test('extractToolCalls falls back to parts when resp.functionCalls is absent', () => {
  const resp = {
    candidates: [{ content: { parts: [
      { functionCall: { name: 'get_weather', args: { city: 'London' } } },
      { text: 'checking now' }
    ] } }]
  };
  const calls = extractToolCalls(resp);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].name, 'get_weather');
});

test('extractToolCalls returns multiple GENUINELY different calls unchanged', () => {
  const resp = {
    functionCalls: [
      { name: 'send_email', args: { to: 'alice@x.com' } },
      { name: 'send_email', args: { to: 'bob@x.com' } }
    ]
  };
  const calls = extractToolCalls(resp);
  assert.equal(calls.length, 2);
  assert.notDeepEqual(calls[0].args, calls[1].args);
});

test('extractToolCalls returns empty array for a pure-text response', () => {
  const resp = { candidates: [{ content: { parts: [{ text: 'all done' }] } }] };
  assert.deepEqual(extractToolCalls(resp), []);
});

test('extractToolCalls handles a missing/malformed response', () => {
  assert.deepEqual(extractToolCalls(null), []);
  assert.deepEqual(extractToolCalls({}), []);
});

test('only batches made entirely of read-only lookups run side by side', () => {
  const { areIndependentReads } = require('../../api/services/agent-orchestrator');
  const call = (type) => ({ type, input: {} });
  assert.equal(areIndependentReads([call('search_flights'), call('search_hotels'), call('get_weather')]), true);
  assert.equal(areIndependentReads([call('search_flights')]), false, 'a single call has nothing to overlap with');
  assert.equal(areIndependentReads([call('search_flights'), call('send_email')]), false);
  assert.equal(areIndependentReads([call('browser_open'), call('get_weather')]), false, 'the browser keeps its order');
  assert.equal(areIndependentReads([call('get_weather'), call('not_a_real_action')]), false);
  assert.equal(areIndependentReads([]), false);
});

test('a run is not cut off by a step count; it goes on until the model answers', async (t) => {
  const brainProvider = require('../../api/services/brain-provider');
  const { runAgentLoop } = require('../../api/services/agent-orchestrator');
  const real = brainProvider.callToolsBrain;
  t.after(() => { brainProvider.callToolsBrain = real; });
  let calls = 0;
  brainProvider.callToolsBrain = async () => {
    if (calls >= 40) return { text: 'Done.', functionCalls: [], candidates: [{ content: { role: 'model', parts: [{ text: 'Done.' }] } }] };
    const args = { step: calls };
    return { text: '', functionCalls: [{ id: 'c', name: 'browser_act', args }], candidates: [{ content: { role: 'model', parts: [{ functionCall: { id: 'c', name: 'browser_act', args } }] } }] };
  };
  const exec = async (_u, actions) => { calls += 1; return actions.map((a) => ({ action: a.type, result: { success: true, text: 'ok' } })); };
  const out = await runAgentLoop({ userId: 'u', initialMessage: 'keep clicking', executeActionsFn: exec });
  assert.equal(calls, 40, 'forty steps ran, far past the old caps of 6 to 20');
  assert.match(out.spoken || out.text || '', /Done/);
});

test('a lookup that already answers in words ends the run without another model pass', async (t) => {
  const brainProvider = require('../../api/services/brain-provider');
  const { runAgentLoop } = require('../../api/services/agent-orchestrator');
  const real = brainProvider.callToolsBrain;
  t.after(() => { brainProvider.callToolsBrain = real; });
  let calls = 0;
  brainProvider.callToolsBrain = async () => {
    calls += 1;
    return { text: '', functionCalls: [{ id: 'c', name: 'get_stock_price', args: {} }], candidates: [{ content: { role: 'model', parts: [{ functionCall: { id: 'c', name: 'get_stock_price', args: {} } }] } }] };
  };
  const exec = async (_u, actions) => actions.map(a => ({ action: a.type, result: { success: true, text: 'AAPL: 190.00 USD.' } }));
  const out = await runAgentLoop({ userId: 'u', initialMessage: 'apple stock price', maxIterations: 4, executeActionsFn: exec });
  assert.equal(out.spoken, 'AAPL: 190.00 USD.');
  assert.equal(calls, 1, 'the answer was already written; no second model pass');
  assert.equal(out.agentTrace.status, 'completed');
});

test('a weather lookup is not spoken verbatim, so the model can answer what was actually asked', () => {
  const { getActionContract } = require('../../api/action-contracts');
  assert.notEqual(getActionContract('get_weather').speaksResult, true);
  assert.notEqual(getActionContract('get_forecast').speaksResult, true);
  assert.match(getActionContract('get_forecast').guidance, /what to wear/);
});

test('a failed model call after tools ran tells the user so instead of dumping tool JSON', async (t) => {
  const brainProvider = require('../../api/services/brain-provider');
  const { runAgentLoop } = require('../../api/services/agent-orchestrator');
  const real = brainProvider.callToolsBrain;
  t.after(() => { brainProvider.callToolsBrain = real; });
  let n = 0;
  brainProvider.callToolsBrain = async () => {
    n += 1;
    if (n === 1) return { text: '', functionCalls: [{ id: 'c', name: 'get_emails', args: {} }], candidates: [{ content: { role: 'model', parts: [{ functionCall: { id: 'c', name: 'get_emails', args: {} } }] } }] };
    throw new Error('provider down');
  };
  const exec = async (_u, actions) => actions.map((a) => ({ action: a.type, result: { success: true, text: 'sunny' } }));
  const out = await runAgentLoop({ userId: 'u', initialMessage: 'weather', maxIterations: 4, executeActionsFn: exec });
  assert.match(out.spoken, /problem/);
  assert.doesNotMatch(out.spoken, /result\]|sunny/);
});

test('the retry after a failed wrap-up call is still tool-free', async (t) => {
  const brainProvider = require('../../api/services/brain-provider');
  const { runAgentLoop } = require('../../api/services/agent-orchestrator');
  const real = brainProvider.callToolsBrain;
  t.after(() => { brainProvider.callToolsBrain = real; });
  const toolCounts = [];
  brainProvider.callToolsBrain = async ({ config }) => {
    const count = (config.tools || []).flatMap((x) => x.functionDeclarations || []).length;
    toolCounts.push(count);
    if (count > 0) return { text: '', functionCalls: [{ id: 'c', name: 'get_weather', args: {} }], candidates: [{ content: { role: 'model', parts: [{ functionCall: { id: 'c', name: 'get_weather', args: {} } }] } }] };
    if (toolCounts.filter((c) => c === 0).length === 1) throw new Error('blip');
    return { text: 'Sunny.', functionCalls: [], candidates: [{ content: { role: 'model', parts: [{ text: 'Sunny.' }] } }] };
  };
  const exec = async (_u, actions) => actions.map((a) => ({ action: a.type, result: { success: true } }));
  await runAgentLoop({ userId: 'u', initialMessage: 'weather', backstopSteps: 3, executeActionsFn: exec });
  const wrapUpCalls = toolCounts.slice(toolCounts.indexOf(0));
  assert.ok(wrapUpCalls.length >= 1 && wrapUpCalls.every((c) => c === 0), JSON.stringify(toolCounts));
});
