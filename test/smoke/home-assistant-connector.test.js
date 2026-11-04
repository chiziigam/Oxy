const assert = require('node:assert/strict');
const test = require('node:test');

const {
  commandToService,
  describeEntity,
  directCommandAllowed,
  executeConfigured,
  listControls,
  homeAssistantConfig,
  resolveEntityId
} = require('../../connectors/home-assistant');

test('Home Assistant maps explicit entity ids and aliases without guessing', () => {
  const env = {
    HOME_ASSISTANT_ENTITY_LIVING_ROOM: 'light.living_room',
    HOME_ASSISTANT_ENTITY_MAP: JSON.stringify({ bedroom: 'switch.bedroom_lamp' })
  };
  assert.equal(resolveEntityId('light.kitchen', env), 'light.kitchen');
  assert.equal(resolveEntityId('living room', env), 'light.living_room');
  assert.equal(resolveEntityId('bedroom', env), 'switch.bedroom_lamp');
  assert.equal(resolveEntityId('unknown', env), null);
});

test('Home Assistant allow-lists simple services and climate temperature changes', () => {
  assert.deepEqual(commandToService('light.living_room', 'on'), {
    domain: 'light', service: 'turn_on', data: { entity_id: 'light.living_room' }
  });
  assert.deepEqual(commandToService('climate.downstairs', 'set 21.5'), {
    domain: 'climate', service: 'set_temperature', data: { entity_id: 'climate.downstairs', temperature: 21.5 }
  });
  assert.match(commandToService('lock.front_door', 'on').error, /does not support/i);
  assert.match(commandToService('light.living_room', 'open').error, /supported/i);
});

test('Home Assistant verifies the state after an accepted service call', async () => {
  const calls = [];
  const request = {
    post: async (...args) => { calls.push(['post', ...args]); },
    get: async (...args) => { calls.push(['get', ...args]); return { data: { state: 'on' } }; }
  };
  const result = await executeConfigured({
    config: { baseUrl: 'http://home.local', token: 'secret' },
    device: 'light.living_room',
    command: 'on',
    request
  });
  assert.equal(result.success, true);
  assert.equal(result.state, 'on');
  assert.equal(calls[0][1], 'http://home.local/api/services/light/turn_on');
  assert.equal(calls[1][1], 'http://home.local/api/states/light.living_room');
  assert.equal(calls[0][2].entity_id, 'light.living_room');
  assert.equal(calls[0][3].headers.Authorization, 'Bearer secret');
});

test('Home Assistant reports accepted-but-unverified commands as incomplete', async () => {
  const result = await executeConfigured({
    config: { baseUrl: 'http://home.local', token: 'secret' },
    device: 'light.living_room',
    command: 'off',
    request: {
      post: async () => {},
      get: async () => { throw new Error('connection reset'); }
    }
  });
  assert.equal(result.success, false);
  assert.equal(result.executed, true);
  assert.equal(result.outcome, 'failed');
  assert.match(result.error, /could not verify/i);
});

test('Home Assistant is explicitly unavailable without both server settings', () => {
  assert.equal(homeAssistantConfig({ HOME_ASSISTANT_URL: 'http://home.local' }), null);
  assert.deepEqual(homeAssistantConfig({ HOME_ASSISTANT_URL: 'http://home.local', HOME_ASSISTANT_TOKEN: 'secret' }), {
    baseUrl: 'http://home.local', token: 'secret'
  });
});

test('Home Assistant maps a light brightness to a percentage, and 0 to off', () => {
  assert.deepEqual(commandToService('light.kitchen', 'brightness 40'), {
    domain: 'light', service: 'turn_on', data: { entity_id: 'light.kitchen', brightness_pct: 40 }
  });
  assert.deepEqual(commandToService('light.kitchen', 'brightness 0'), {
    domain: 'light', service: 'turn_off', data: { entity_id: 'light.kitchen' }
  });
  assert.match(commandToService('switch.kettle', 'brightness 40').error, /requires a light/i);
});

test('Home controls describe state and capabilities without inventing either', () => {
  const lamp = describeEntity(
    { entity_id: 'light.lamp', state: 'on', attributes: { brightness: 255, friendly_name: 'Lamp' }, last_updated: '2026-11-04T01:00:00Z' },
    { room: 'Living room' }
  );
  assert.deepEqual(
    [lamp.name, lamp.room, lamp.isOn, lamp.brightness, lamp.capabilities],
    ['Lamp', 'Living room', true, 100, ['toggle', 'brightness']]
  );
  const gone = describeEntity({ entity_id: 'switch.heater', state: 'unavailable', attributes: {} });
  assert.deepEqual([gone.available, gone.isOn, gone.state, gone.capabilities], [false, false, 'unavailable', []]);
  const door = describeEntity({ entity_id: 'cover.garage', state: 'open', attributes: {} });
  assert.deepEqual(door.capabilities, [], 'covers get no one-tap control');
  const heat = describeEntity({ entity_id: 'climate.hall', state: 'heat', attributes: { current_temperature: 19.5, temperature: 21 } });
  assert.deepEqual([heat.temperature, heat.targetTemperature, heat.capabilities], [19.5, 21, ['temperature']]);
});

test('direct Home commands are limited to what the device reports it can do', () => {
  const lamp = { available: true, capabilities: ['toggle', 'brightness'] };
  assert.equal(directCommandAllowed(lamp, 'off'), true);
  assert.equal(directCommandAllowed(lamp, 'brightness 30'), true);
  assert.equal(directCommandAllowed(lamp, 'set 21'), false);
  assert.equal(directCommandAllowed({ available: true, capabilities: [] }, 'on'), false);
  assert.equal(directCommandAllowed({ available: false, capabilities: ['toggle'] }, 'on'), false);
});

test('Home controls are not_configured without a server, unavailable when it does not answer', async () => {
  assert.equal((await listControls({ config: null })).status, 'not_configured');
  const down = await listControls({
    config: { baseUrl: 'http://home.local', token: 't' },
    env: {},
    request: { get: async () => { throw new Error('ECONNREFUSED'); } }
  });
  assert.deepEqual([down.status, down.controls], ['unavailable', []]);
});

test('Home controls list named entities with their aliases and rooms', async () => {
  const seen = [];
  const result = await listControls({
    config: { baseUrl: 'http://home.local', token: 't' },
    env: {
      HOME_ASSISTANT_ENTITY_MAP: JSON.stringify({ 'desk lamp': 'light.desk' }),
      HOME_ASSISTANT_ROOM_MAP: JSON.stringify({ 'light.desk': 'Study' })
    },
    request: { get: async url => { seen.push(url); return { data: { entity_id: 'light.desk', state: 'off', attributes: {} } }; } }
  });
  assert.deepEqual(seen, ['http://home.local/api/states/light.desk']);
  assert.equal(result.status, 'ok');
  assert.deepEqual([result.controls[0].name, result.controls[0].room, result.controls[0].isOn], ['Desk Lamp', 'Study', false]);
});
