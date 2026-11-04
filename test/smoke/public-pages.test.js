const assert = require('node:assert/strict');
const http = require('node:http');
const test = require('node:test');

process.env.SUPABASE_URL = process.env.SUPABASE_URL || 'https://example.supabase.co';
process.env.SUPABASE_KEY = process.env.SUPABASE_KEY || 'test-key';
process.env.OXY_SESSION_SECRET = process.env.OXY_SESSION_SECRET || 'test-session-secret';
process.env.OPENAI_API_KEY = process.env.OPENAI_API_KEY || 'test-openai-key';

const app = require('../../api/index');
let server;
let port;

test.before(async () => {
  server = await new Promise(resolve => {
    const instance = app.listen(0, '127.0.0.1', () => resolve(instance));
  });
  port = server.address().port;
});

test.after(async () => {
  await new Promise(resolve => server.close(resolve));
});

function request(path, options = {}) {
  return new Promise((resolve, reject) => {
    const req = http.request({ hostname: '127.0.0.1', port, path, ...options }, res => {
      let body = '';
      res.setEncoding('utf8');
      res.on('data', chunk => { body += chunk; });
      res.on('end', () => resolve({ status: res.statusCode, body, headers: res.headers }));
    });
    req.on('error', reject);
    if (options.body) req.write(options.body);
    req.end();
  });
}

test('the public home page is HTML, not the missing PWA file', async () => {
  const home = await request('/');
  assert.equal(home.status, 200);
  assert.match(home.headers['content-type'], /text\/html/);
  assert.match(home.body, /A personal assistant/);
  assert.match(home.body, /href="\/privacy"/);
  assert.match(home.body, /name="viewport"/);
  assert.equal(home.body.includes('That request was not valid'), false);
  assert.equal(home.body.includes('index.html'), false);
});

test('password reset and email links are readable pages', async () => {
  const missing = await request('/auth/reset-password');
  assert.equal(missing.status, 200);
  assert.match(missing.body, /Reset link missing/);
  assert.match(missing.body, /name="viewport"/);

  const form = await request('/auth/reset-password?token=exampletoken');
  assert.match(form.body, /name="newPassword"/);
  assert.match(form.body, /Reset password/);
  assert.match(form.body, /value="exampletoken"/);

  const bad = await request('/auth/reset-password', {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: 'token=not-a-real-token&newPassword=short'
  });
  assert.equal(bad.status, 400);
  assert.match(bad.headers['content-type'], /text\/html/);
  assert.match(bad.body, /at least 8 characters/i);

  const api = await request('/auth/reset-password', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ token: 'not-a-real-token', newPassword: 'short' })
  });
  assert.equal(api.status, 400);
  assert.match(api.headers['content-type'], /json/);
  assert.equal(JSON.parse(api.body).error, 'Password must be at least 8 characters.');

  const verify = await request('/auth/verify-email/confirm?token=not-a-token');
  assert.match(verify.body, /not valid/);
  assert.match(verify.body, /name="viewport"/);
});

test('legal pages and the display receiver keep their jobs', async () => {
  const privacy = await request('/privacy');
  assert.equal(privacy.status, 200);
  assert.match(privacy.body, /Privacy Policy/);
  assert.match(privacy.body, /name="viewport"/);
  const support = await request('/support');
  assert.match(support.body, /Delete your account/);
  const display = await request('/display?challenge=demo');
  assert.equal(display.status, 200);
  assert.match(display.body, /Pair this screen/);
  assert.match(display.body, /speechSynthesis/);
  assert.equal(display.body.includes('#e97961'), false);
});
