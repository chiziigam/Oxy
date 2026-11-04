const assert = require('node:assert/strict');
const test = require('node:test');

const weather = require('../../connectors/weather');

const PLACE = { name: 'London', country: 'United Kingdom' };
const READINGS = {
  current: { temperature_2m: 12.4, apparent_temperature: 10.2, relative_humidity_2m: 80, precipitation: 0, weather_code: 3, wind_speed_10m: 14.3 },
  daily: {
    time: ['2026-11-04', '2026-11-05', '2026-11-06'],
    weather_code: [3, 61, 0],
    temperature_2m_max: [14.2, 13.8, 15.1],
    temperature_2m_min: [8.6, 9.4, 7.2],
    precipitation_probability_max: [20, 70, 5]
  }
};

test('current conditions read as one plain sentence', () => {
  const text = weather.formatReadings(PLACE, READINGS, { forecast: false });
  assert.equal(text, 'London: 12°C, overcast, feels like 10°C, wind 14 km/h.');
});

test('a forecast names the day and gives a range and rain chance', () => {
  const tomorrow = weather.formatReadings(PLACE, READINGS, { forecast: true, when: 'tomorrow' });
  assert.match(tomorrow, /2026-11-05: light rain, 9°C to 14°C, 70% chance of rain\./);
  assert.doesNotMatch(tomorrow, /2026-11-06/, 'only the day that was asked about');
});

test('a forecast with no stated day gives the next two days', () => {
  const text = weather.formatReadings(PLACE, READINGS, { forecast: true });
  assert.match(text, /2026-11-05/);
  assert.match(text, /2026-11-06/);
  assert.doesNotMatch(text, /2026-11-04/, 'today is already covered by the current reading');
});

test('every code the API can send has words, and unknown codes stay honest', () => {
  assert.equal(weather.describe(61), 'light rain');
  assert.equal(weather.describe(95), 'thunderstorm');
  assert.equal(weather.describe(1234), 'mixed conditions');
});

test('the day asked for is the day answered', () => {
  assert.equal(weather.requestedDayIndex('tomorrow'), 1);
  assert.equal(weather.requestedDayIndex('today'), 0);
  assert.equal(weather.requestedDayIndex('this weekend'), null);
});

test('a working API answer never falls back to a web search', async () => {
  const original = global.fetch;
  const urls = [];
  global.fetch = async url => {
    urls.push(String(url));
    if (String(url).includes('geocoding')) return { ok: true, json: async () => ({ results: [{ name: 'London', country: 'United Kingdom', latitude: 51.5, longitude: -0.12 }] }) };
    return { ok: true, json: async () => READINGS };
  };
  try {
    const result = await weather.execute('u1', 'get_forecast', { city: 'London', when: 'tomorrow' });
    assert.equal(result.source, 'open-meteo');
    assert.match(result.text, /light rain/);
    assert.equal(urls.length, 2, 'one lookup, one reading');
  } finally {
    global.fetch = original;
  }
});
