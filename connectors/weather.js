const brainProvider = require('../api/services/brain-provider');
const { defaultModelForProvider } = require('../api/services/model-routing');

// WMO weather codes, the vocabulary Open-Meteo returns.
const CONDITIONS = {
  0: 'clear', 1: 'mostly clear', 2: 'partly cloudy', 3: 'overcast',
  45: 'fog', 48: 'freezing fog',
  51: 'light drizzle', 53: 'drizzle', 55: 'heavy drizzle',
  56: 'freezing drizzle', 57: 'freezing drizzle',
  61: 'light rain', 63: 'rain', 65: 'heavy rain',
  66: 'freezing rain', 67: 'freezing rain',
  71: 'light snow', 73: 'snow', 75: 'heavy snow', 77: 'snow grains',
  80: 'light showers', 81: 'showers', 82: 'heavy showers',
  85: 'snow showers', 86: 'heavy snow showers',
  95: 'thunderstorm', 96: 'thunderstorm with hail', 99: 'thunderstorm with hail'
};

const TIMEOUT_MS = Number(process.env.OXY_WEATHER_TIMEOUT_MS || 6000);

function describe(code) {
  return CONDITIONS[code] || 'mixed conditions';
}

function round(value) {
  return Number.isFinite(value) ? Math.round(value) : null;
}

async function getJSON(url) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), TIMEOUT_MS);
  try {
    const res = await fetch(url, { signal: controller.signal });
    if (!res.ok) throw new Error(`Open-Meteo ${res.status}`);
    return await res.json();
  } finally {
    clearTimeout(timeout);
  }
}

async function placeFor(city) {
  const url = `https://geocoding-api.open-meteo.com/v1/search?name=${encodeURIComponent(city)}&count=1&language=en&format=json`;
  const json = await getJSON(url);
  const hit = json?.results?.[0];
  if (!hit) throw new Error(`no place matched "${city}"`);
  return { name: hit.name, country: hit.country, latitude: hit.latitude, longitude: hit.longitude, timezone: hit.timezone };
}

async function readingsFor(place) {
  const url = 'https://api.open-meteo.com/v1/forecast'
    + `?latitude=${place.latitude}&longitude=${place.longitude}`
    + '&current=temperature_2m,apparent_temperature,relative_humidity_2m,precipitation,weather_code,wind_speed_10m'
    + '&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max'
    + '&timezone=auto&forecast_days=4';
  return getJSON(url);
}

function currentLine(place, json) {
  const now = json?.current;
  if (!now) return null;
  const parts = [`${round(now.temperature_2m)}°C`, describe(now.weather_code)];
  if (Number.isFinite(now.apparent_temperature)) parts.push(`feels like ${round(now.apparent_temperature)}°C`);
  if (Number.isFinite(now.wind_speed_10m)) parts.push(`wind ${round(now.wind_speed_10m)} km/h`);
  if (Number.isFinite(now.precipitation) && now.precipitation > 0) parts.push(`${now.precipitation} mm of rain now`);
  return `${place.name}: ${parts.join(', ')}.`;
}

function dayLine(place, json, index) {
  const daily = json?.daily;
  if (!daily?.time?.[index]) return null;
  const parts = [describe(daily.weather_code?.[index])];
  const high = round(daily.temperature_2m_max?.[index]);
  const low = round(daily.temperature_2m_min?.[index]);
  if (high !== null && low !== null) parts.push(`${low}°C to ${high}°C`);
  const rain = daily.precipitation_probability_max?.[index];
  if (Number.isFinite(rain)) parts.push(`${rain}% chance of rain`);
  return `${daily.time[index]}: ${parts.join(', ')}.`;
}

// "tomorrow" and "today" are the only offsets worth guessing; anything else gets the next days.
function requestedDayIndex(when) {
  const text = String(when || '').toLowerCase();
  if (/\b(today|tonight|now|currently)\b/.test(text)) return 0;
  if (/\btomorrow\b/.test(text)) return 1;
  return null;
}

function formatReadings(place, json, { forecast = false, when = '' } = {}) {
  const lines = [];
  const current = currentLine(place, json);
  if (current) lines.push(current);
  if (forecast) {
    const index = requestedDayIndex(when);
    if (index === null) {
      for (let i = 1; i <= 2; i += 1) {
        const line = dayLine(place, json, i);
        if (line) lines.push(line);
      }
    } else {
      const line = dayLine(place, json, index);
      if (line) lines.push(line);
    }
  }
  return lines.join(' ');
}

async function openMeteoWeather(city, forecast, when) {
  const place = await placeFor(city);
  const json = await readingsFor(place);
  const text = formatReadings(place, json, { forecast, when });
  if (!text) throw new Error('no readings in the response');
  return { success: true, outcome: 'completed', text, city: place.name, source: 'open-meteo' };
}

// Kept as the fallback for places Open-Meteo cannot resolve, so the capability never vanishes.
function searchModel() {
  return defaultModelForProvider(process.env.OXY_BRAIN_PROVIDER || 'openai', 'fast');
}

async function groundedWeather(city, forecast = false, when = '') {
  const today = new Date().toISOString().slice(0, 10);
  const period = when ? ` for ${when}` : '';
  const prompt = forecast
    ? `Today's date is ${today}. Search the web for the current weather forecast for ${city}${period}. Return the next useful forecast periods, temperatures, precipitation and wind where available, with the relevant update time. Only report facts supported by the search results; say plainly if a detail is unavailable. Plain concise text.`
    : `Today's date is ${today}. Search the web for the current weather in ${city}. Return the current temperature, conditions, feels-like temperature and precipitation or wind where available, with the relevant observation or update time. Only report facts supported by the search results; say plainly if current data is unavailable. Plain concise text.`;
  const text = await brainProvider.webSearchBrain({ model: searchModel(), prompt });
  if (!text) {
    return {
      success: false,
      outcome: 'unavailable',
      unavailable: true,
      error: `No grounded weather result was available for ${city}.`
    };
  }
  return { success: true, outcome: 'completed', text, city, source: 'grounded_web_search' };
}

async function execute(userId, action, params) {
  const city = params.city || params.location || 'London';
  const forecast = action === 'get_forecast';
  if (action !== 'get_weather' && action !== 'get_forecast') {
    return { success: false, outcome: 'failed', error: 'Unknown weather action' };
  }
  try {
    return await openMeteoWeather(city, forecast, params.when);
  } catch {
    // A real reading was unavailable; fall back rather than failing the turn.
  }
  try {
    return await groundedWeather(city, forecast, params.when);
  } catch (e) {
    return { success: false, outcome: 'failed', error: `Weather search failed: ${e.message}` };
  }
}

module.exports = { execute, formatReadings, describe, requestedDayIndex };
