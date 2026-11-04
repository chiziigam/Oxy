'use strict';
// A handover, not a bypass. When a site asks for a step only a person can do — a CAPTCHA, a
// one-time code, a passkey, a bank's own confirmation — the agent stops and offers the live
// screen. The person finishes that one step and hands it back; everything around it stays
// automated. This is how the assistants that do this well behave, and it is also the honest
// answer for anything a retailer refuses to let a robot near.

const { signPayload, verifySignedPayload } = require('../../auth');

const TAKEOVER_TTL_MS = 10 * 60 * 1000;

function createTakeoverUrl(userId) {
  const token = signPayload({ type: 'browser_takeover', userId }, TAKEOVER_TTL_MS);
  return `/takeover/${token}`;
}

function readTakeoverToken(token) {
  const payload = verifySignedPayload(token);
  if (!payload || payload.type !== 'browser_takeover' || !payload.userId) return null;
  return { userId: payload.userId };
}

// What the person sees: the live screen, as bytes.
async function frame(userId) {
  const environment = require('./browser-environment');
  const session = require('./browser-session').getSession(userId);
  if (!session) throw new Error('No page is open.');
  return environment.screenshotJpeg(session.page);
}

// What the person does: one click, one key, one line of text, applied to that same page.
async function applyAction(userId, step = {}) {
  const { getSession, touchSession } = require('./browser-session');
  const session = getSession(userId);
  if (!session) throw new Error('No page is open.');
  touchSession(userId);
  const page = session.page;
  const kind = String(step.type || step.action || '').toLowerCase();

  if (kind === 'click') {
    const x = Number(step.x);
    const y = Number(step.y);
    if (!Number.isFinite(x) || !Number.isFinite(y)) throw new Error('A click needs x and y.');
    await page.mouse.click(x, y);
  } else if (kind === 'type') {
    await page.keyboard.type(String(step.text ?? ''));
  } else if (kind === 'key') {
    await page.keyboard.press(String(step.text || 'Enter'));
  } else if (kind === 'back') {
    await page.goBack().catch(() => {});
  } else if (kind === 'done') {
    return { ok: true, done: true };
  } else {
    throw new Error(`Unknown takeover action "${kind}".`);
  }

  await page.waitForTimeout(600);
  return { ok: true };
}

// The page itself: a live picture, a tap target, and a text line. Deliberately small — it has
// to work on a phone, over a bad connection, on a screen that is 1280 wide at the other end.
const PAGE = `<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>Adam needs a hand</title>
<style>
  :root { color-scheme: light dark; }
  body { margin:0; font:16px -apple-system,system-ui,sans-serif; background:#f2f2f7; color:#111; }
  @media (prefers-color-scheme: dark){ body{background:#000;color:#fff} header{background:#1c1c1e!important} }
  header { position:sticky; top:0; padding:12px 16px; background:#fff; border-bottom:1px solid #d8d8dc; }
  h1 { margin:0; font-size:17px; font-weight:600; }
  p { margin:4px 0 0; font-size:13px; color:#6b6b70; }
  #screen { display:block; width:100%; height:auto; background:#888; touch-action:manipulation; }
  .bar { position:sticky; bottom:0; display:flex; gap:8px; padding:10px 12px; background:#fff; border-top:1px solid #d8d8dc; }
  @media (prefers-color-scheme: dark){ .bar{background:#1c1c1e} }
  input { flex:1; min-width:0; font-size:16px; padding:12px; border-radius:12px; border:1px solid #c7c7cc; background:transparent; color:inherit; }
  button { font-size:15px; font-weight:600; padding:12px 16px; border-radius:12px; border:0; background:#111; color:#fff; }
  @media (prefers-color-scheme: dark){ button{background:#fff;color:#000} }
</style></head>
<body>
<header><h1>Adam needs a hand</h1><p>Finish the step only you can do, then tap Done.</p></header>
<img id="screen" alt="The page Adam is on">
<div class="bar">
  <input id="text" placeholder="Type into the page&#8230;" autocapitalize="off" autocorrect="off">
  <button id="send">Type</button>
  <button id="done">Done</button>
</div>
<script>
  const token = location.pathname.split('/').pop();
  const screen = document.getElementById('screen');
  let busy = false;
  async function frame() {
    try {
      const r = await fetch('/takeover/' + token + '/frame', { cache: 'no-store' });
      if (!r.ok) throw new Error('frame');
      const blob = await r.blob();
      const url = URL.createObjectURL(blob);
      const previous = screen.src;
      screen.src = url;
      if (previous) URL.revokeObjectURL(previous);
    } catch (e) { /* keep the last frame */ }
    setTimeout(frame, 1200);
  }
  async function send(body) {
    await fetch('/takeover/' + token + '/action', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(body)
    }).catch(() => {});
  }
  screen.addEventListener('click', (event) => {
    const rect = screen.getBoundingClientRect();
    const x = Math.round((event.clientX - rect.left) * (screen.naturalWidth / rect.width));
    const y = Math.round((event.clientY - rect.top) * (screen.naturalHeight / rect.height));
    send({ type: 'click', x, y });
  });
  document.getElementById('send').addEventListener('click', () => {
    const field = document.getElementById('text');
    if (!field.value) return;
    send({ type: 'type', text: field.value });
    field.value = '';
  });
  document.getElementById('text').addEventListener('keydown', (e) => {
    if (e.key === 'Enter') { e.preventDefault(); document.getElementById('send').click(); }
  });
  document.getElementById('done').addEventListener('click', async () => {
    await send({ type: 'done' });
    document.body.innerHTML = '<header><h1>Handed back</h1><p>Adam is carrying on.</p></header>';
  });
  frame();
</script>
</body></html>`;

function pageHtml() {
  return PAGE;
}

module.exports = { createTakeoverUrl, readTakeoverToken, frame, applyAction, pageHtml, TAKEOVER_TTL_MS };
