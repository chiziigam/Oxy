const assert = require('node:assert/strict');
const test = require('node:test');

process.env.SUPABASE_URL = process.env.SUPABASE_URL || 'https://example.supabase.co';
process.env.SUPABASE_KEY = process.env.SUPABASE_KEY || 'test-key';

const { buildToolsForGemini, ACTION_CONTRACTS } = require('../../api/action-contracts');
const { ROOM_DEVICE_TOOLS, toolsForChannel, reasoningEffortForChannel } = require('../../api/services/chat-channel');

const names = tools => tools[0].functionDeclarations.map(d => d.name);
const moneyAndBrowsing = ['stripe_charge', 'browser_act', 'transaction_authorize', 'workspace_write'];

test('a room speaker is sent a small budget of capabilities, not every one the phone has', () => {
  const room = toolsForChannel('display');
  assert.ok(Array.isArray(room) && room.length > 0);

  const phone = names(buildToolsForGemini(false));
  const speaker = names(buildToolsForGemini(false, { only: room }));

  assert.ok(phone.length > 100, 'the full surface keeps every capability');
  assert.ok(speaker.length <= 30, `the speaker got ${speaker.length}`);
  assert.ok(speaker.length < phone.length / 3, 'the budget must actually shrink the request');
  for (const type of speaker) assert.ok(ACTION_CONTRACTS[type], `${type} must be a real contract`);
});

test('the speaker keeps the things you would actually say out loud in a room', () => {
  const speaker = names(buildToolsForGemini(false, { only: toolsForChannel('display') }));
  for (const type of ['web_search', 'get_weather', 'get_calendar_events', 'create_reminder', 'create_agent_task']) {
    assert.ok(speaker.includes(type), `${type} must stay available in the room`);
  }
});

test('spending and long-form work do not sit in the room', () => {
  const speaker = names(buildToolsForGemini(false, { only: toolsForChannel('display') }));
  for (const type of moneyAndBrowsing) {
    assert.ok(!speaker.includes(type), `${type} belongs on the phone`);
  }
  // Anything bigger is still reachable: it is handed off, not refused.
  assert.ok(speaker.includes('create_agent_task'));
});

test('every other surface keeps the full set', () => {
  assert.equal(toolsForChannel(null), null);
  assert.equal(toolsForChannel('ios'), null);
  assert.equal(toolsForChannel('telegram_bot'), null);
  assert.equal(names(buildToolsForGemini(false, {})).length, names(buildToolsForGemini(false)).length);
});

test('the room answers out loud without deep reasoning, and can be tuned', () => {
  assert.equal(reasoningEffortForChannel('display'), 'low');
  assert.equal(reasoningEffortForChannel(null), null);
  assert.equal(reasoningEffortForChannel('ios'), null);
  assert.equal(reasoningEffortForChannel('display', { OXY_ROOM_REASONING_EFFORT: 'medium' }), 'medium');
});
