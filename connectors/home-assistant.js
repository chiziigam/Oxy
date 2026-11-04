'use strict';

const axios = require('axios');

function clean(value, max = 180) {
  const text = String(value || '').replace(/\s+/g, ' ').trim();
  return text.length > max ? text.slice(0, max) : text;
}

function homeAssistantConfig(env = process.env) {
  const baseUrl = String(env.HOME_ASSISTANT_URL || '').trim().replace(/\/+$/, '');
  const token = String(env.HOME_ASSISTANT_TOKEN || '').trim();
  return baseUrl && token ? { baseUrl, token } : null;
}

function resolveEntityId(device, env = process.env) {
  const explicit = String(device || '').trim().toLowerCase();
  if (/^[a-z][a-z0-9_]+\.[a-z0-9_]+$/.test(explicit)) return explicit;

  const key = explicit.replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '').toUpperCase();
  const mapped = String(env[`HOME_ASSISTANT_ENTITY_${key}`] || '').trim().toLowerCase();
  if (/^[a-z][a-z0-9_]+\.[a-z0-9_]+$/.test(mapped)) return mapped;

  try {
    const map = JSON.parse(String(env.HOME_ASSISTANT_ENTITY_MAP || '{}'));
    const fromMap = String(map[explicit] || '').trim().toLowerCase();
    if (/^[a-z][a-z0-9_]+\.[a-z0-9_]+$/.test(fromMap)) return fromMap;
  } catch {
    // A malformed optional map is equivalent to no alias; the explicit entity-id path still
    // works and the returned error tells the user what configuration is missing.
  }
  return null;
}

function commandToService(entityId, command) {
  const [domain] = entityId.split('.');
  const text = String(command || '').trim().toLowerCase();
  if (!text) return { error: 'A smart-home command is required.' };

  if (['on', 'off', 'toggle'].includes(text)) {
    const supported = new Set(['light', 'switch', 'fan', 'input_boolean', 'group', 'cover']);
    if (!supported.has(domain)) return { error: `The ${domain} domain does not support a simple ${text} command.` };
    const service = domain === 'cover'
      ? (text === 'on' ? 'open_cover' : text === 'off' ? 'close_cover' : 'toggle')
      : (text === 'toggle' ? 'toggle' : `turn_${text}`);
    return { domain, service, data: { entity_id: entityId } };
  }

  const brightness = text.match(/^brightness\s+(\d{1,3})\s*%?$/i);
  if (brightness) {
    if (domain !== 'light') return { error: 'A brightness command requires a light entity.' };
    const pct = Math.min(100, Math.max(0, Number(brightness[1])));
    if (pct === 0) return { domain, service: 'turn_off', data: { entity_id: entityId } };
    return { domain, service: 'turn_on', data: { entity_id: entityId, brightness_pct: pct } };
  }

  const temperature = text.match(/^set(?:\s+temperature)?\s+(-?\d+(?:\.\d+)?)\s*(?:°?c)?$/i);
  if (temperature) {
    if (domain !== 'climate') return { error: 'A temperature command requires a climate entity.' };
    return {
      domain,
      service: 'set_temperature',
      data: { entity_id: entityId, temperature: Number(temperature[1]) }
    };
  }

  return { error: 'Supported smart-home commands are on, off, toggle, brightness <0-100>, or set <temperature>.' };
}

// The domains Home lists as controls. Covers (garage doors, blinds) are shown with their state but
// get no one-tap control: opening one stays a request to Adam, which goes through review.
const CONTROL_DOMAINS = new Set(['light', 'switch', 'fan', 'input_boolean', 'climate', 'cover']);
const TOGGLE_DOMAINS = new Set(['light', 'switch', 'fan', 'input_boolean']);
const MAX_CONTROLS = 40;
const ENTITY_RE = /^[a-z][a-z0-9_]+\.[a-z0-9_]+$/;

function parseJsonObject(raw) {
  try {
    const value = JSON.parse(String(raw || '{}'));
    return value && typeof value === 'object' && !Array.isArray(value) ? value : {};
  } catch {
    return {};
  }
}

// Entities the household has named for Adam: HOME_ASSISTANT_ENTITY_MAP aliases and
// HOME_ASSISTANT_ENTITY_<ALIAS> variables. When none are named, Home lists every controllable entity.
function configuredEntities(env = process.env) {
  const named = new Map();
  for (const [alias, entity] of Object.entries(parseJsonObject(env.HOME_ASSISTANT_ENTITY_MAP))) {
    const id = String(entity || '').trim().toLowerCase();
    if (ENTITY_RE.test(id) && !named.has(id)) named.set(id, clean(alias, 60));
  }
  for (const [key, value] of Object.entries(env)) {
    const match = key.match(/^HOME_ASSISTANT_ENTITY_([A-Z0-9_]+)$/);
    if (!match || match[1] === 'MAP') continue;
    const id = String(value || '').trim().toLowerCase();
    if (ENTITY_RE.test(id) && !named.has(id)) named.set(id, clean(match[1].replace(/_/g, ' ').toLowerCase(), 60));
  }
  return [...named.entries()].map(([entityId, alias]) => ({ entityId, alias }));
}

function titleCase(text) {
  return String(text || '').replace(/(^|\s)\S/g, ch => ch.toUpperCase());
}

function finiteNumber(value) {
  const n = Number(value);
  return value !== null && value !== undefined && value !== '' && Number.isFinite(n) ? n : null;
}

// One Home Assistant state object as a Home control. Unknown and unavailable stay explicit.
function describeEntity(stateObject, { alias = null, room = null } = {}) {
  const entityId = String(stateObject?.entity_id || '').toLowerCase();
  if (!ENTITY_RE.test(entityId)) return null;
  const [domain] = entityId.split('.');
  const attributes = stateObject?.attributes && typeof stateObject.attributes === 'object' ? stateObject.attributes : {};
  const rawState = clean(stateObject?.state || 'unknown', 40).toLowerCase();
  const available = !['unavailable', 'unknown', ''].includes(rawState);
  const capabilities = [];
  if (available && TOGGLE_DOMAINS.has(domain)) capabilities.push('toggle');
  const modes = Array.isArray(attributes.supported_color_modes) ? attributes.supported_color_modes : [];
  if (available && domain === 'light' && (finiteNumber(attributes.brightness) !== null || modes.some(mode => mode !== 'onoff'))) {
    capabilities.push('brightness');
  }
  if (available && domain === 'climate') capabilities.push('temperature');
  const brightness = finiteNumber(attributes.brightness);
  const isOn = available && (domain === 'climate' ? rawState !== 'off' : (domain === 'cover' ? rawState === 'open' : rawState === 'on'));
  return {
    id: entityId,
    name: clean(alias ? titleCase(alias) : (attributes.friendly_name || entityId.split('.')[1].replace(/_/g, ' ')), 60),
    room: clean(room, 40) || null,
    kind: domain,
    state: available ? rawState : (rawState === 'unavailable' ? 'unavailable' : 'unknown'),
    available,
    isOn,
    brightness: brightness === null || rawState !== 'on' ? null : Math.round((brightness / 255) * 100),
    temperature: finiteNumber(attributes.current_temperature),
    targetTemperature: finiteNumber(attributes.temperature),
    minTemperature: finiteNumber(attributes.min_temp),
    maxTemperature: finiteNumber(attributes.max_temp),
    capabilities,
    updatedAt: clean(stateObject?.last_updated || stateObject?.last_changed, 40) || null
  };
}

// What Home shows about smart-home devices: read-only, never a side effect. A missing server
// configuration is "not_configured"; an unreachable server is "unavailable", never an empty home.
async function listControls({ config = homeAssistantConfig(), env = process.env, request = axios, timeout = 4000 } = {}) {
  if (!config) return { status: 'not_configured', detail: null, controls: [] };
  const headers = { Authorization: `Bearer ${config.token}`, 'Content-Type': 'application/json' };
  const rooms = parseJsonObject(env.HOME_ASSISTANT_ROOM_MAP);
  const named = configuredEntities(env);
  try {
    let objects;
    if (named.length) {
      const settled = await Promise.allSettled(named.slice(0, MAX_CONTROLS).map(item =>
        request.get(`${config.baseUrl}/api/states/${item.entityId}`, { headers, timeout })));
      objects = settled.map((entry, index) => entry.status === 'fulfilled' && entry.value?.data
        ? entry.value.data
        : { entity_id: named[index].entityId, state: 'unavailable', attributes: {} });
    } else {
      const response = await request.get(`${config.baseUrl}/api/states`, { headers, timeout });
      objects = (Array.isArray(response?.data) ? response.data : [])
        .filter(item => CONTROL_DOMAINS.has(String(item?.entity_id || '').split('.')[0]))
        .slice(0, MAX_CONTROLS);
    }
    const aliasFor = new Map(named.map(item => [item.entityId, item.alias]));
    const controls = objects
      .filter(item => CONTROL_DOMAINS.has(String(item?.entity_id || '').split('.')[0]))
      .map(item => describeEntity(item, {
        alias: aliasFor.get(String(item.entity_id).toLowerCase()) || null,
        room: rooms[String(item.entity_id).toLowerCase()] || null
      }))
      .filter(Boolean);
    return { status: 'ok', detail: null, controls };
  } catch {
    return { status: 'unavailable', detail: 'Home Assistant did not answer.', controls: [] };
  }
}

// The commands a person can send from a Home control, checked against what the device reports.
function directCommandAllowed(control, command) {
  const text = String(command || '').trim().toLowerCase();
  if (!control?.available) return false;
  const caps = new Set(control.capabilities || []);
  if (['on', 'off', 'toggle'].includes(text)) return caps.has('toggle');
  if (/^brightness\s+\d{1,3}$/.test(text)) return caps.has('brightness');
  if (/^set\s+-?\d+(?:\.\d+)?$/.test(text)) return caps.has('temperature');
  return false;
}

async function executeConfigured({ config, device, command, request = axios } = {}) {
  const entityId = resolveEntityId(device);
  if (!entityId) {
    return {
      success: false,
      outcome: 'unavailable',
      unavailable: true,
      error: 'That smart-home device is not mapped. Use its Home Assistant entity id or configure HOME_ASSISTANT_ENTITY_MAP.'
    };
  }
  const service = commandToService(entityId, command);
  if (service.error) return { success: false, outcome: 'failed', error: service.error };

  const headers = { Authorization: `Bearer ${config.token}`, 'Content-Type': 'application/json' };
  const serviceUrl = `${config.baseUrl}/api/services/${service.domain}/${service.service}`;
  try {
    await request.post(serviceUrl, service.data, { headers, timeout: 15000 });
  } catch (error) {
    return {
      success: false,
      outcome: 'failed',
      error: `Home Assistant did not accept the command: ${clean(error.response?.data?.message || error.message)}`
    };
  }

  // A 200 from the service endpoint means HA accepted the request, not that the device
  // reached the requested state. Read it back before reporting success.
  try {
    const state = await request.get(`${config.baseUrl}/api/states/${entityId}`, { headers, timeout: 15000 });
    const current = clean(state.data?.state || 'unknown', 60);
    return {
      success: true,
      text: `${entityId} is now ${current}.`,
      entityId,
      state: current,
      command: service.service
    };
  } catch (error) {
    return {
      success: false,
      outcome: 'failed',
      executed: true,
      entityId,
      error: `Home Assistant accepted the command for ${entityId}, but I could not verify its state: ${clean(error.message)}`
    };
  }
}

async function execute(_userId, action, params = {}) {
  if (action !== 'control_smart_home') return { success: false, error: 'Unknown Home Assistant action.' };
  const config = homeAssistantConfig();
  if (!config) {
    return {
      success: false,
      outcome: 'unavailable',
      unavailable: true,
      error: 'Smart-home control is unavailable until HOME_ASSISTANT_URL and HOME_ASSISTANT_TOKEN are configured.'
    };
  }
  return executeConfigured({ config, device: params.device || params.entity_id, command: params.command });
}

module.exports = {
  execute,
  commandToService,
  configuredEntities,
  describeEntity,
  directCommandAllowed,
  listControls,
  homeAssistantConfig,
  resolveEntityId,
  executeConfigured
};
