const assert = require('node:assert/strict');
const test = require('node:test');

const { handlers } = require('../../api/actions/display');
const { getActionContract } = require('../../api/action-contracts');

const run = params => handlers.make_game({ params });

const goodGame = `<div id="app"><p id="msg">Pick a number from 1 to 3</p><button id="b1">1</button><button id="b2">2</button></div>
<style>#app{text-align:center}button{min-height:44px}</style>
<script>var n=Math.ceil(Math.random()*3);document.getElementById('b1').onclick=function(){document.getElementById('msg').textContent=n===1?'Yes':'No'};</script>`;

test('a self-contained page becomes a playable result', async () => {
  const result = await run({ title: '  Number   pick ', html: goodGame });
  assert.equal(result.success, true);
  assert.equal(result.playable.title, 'Number pick');
  assert.equal(result.playable.html, goodGame.trim());
  assert.match(result.text, /Tap Play/);
});

test('page structure tags and the doctype are removed so the phone can wrap the body itself', async () => {
  const result = await run({ title: 'Wrapped', html: `<!DOCTYPE html><html lang="en"><head><title>x</title></head><body class="a">${goodGame}</body></html>` });
  assert.equal(result.success, true);
  assert.doesNotMatch(result.playable.html, /<!doctype|<\/?html|<\/?head|<\/?body/i);
  assert.match(result.playable.html, /id="app"/);
});

test('a page that reaches for the internet or saved data is sent back to be rewritten', async () => {
  const bad = [
    `${goodGame}<script>fetch('/x')</script>`,
    `${goodGame}<script>new WebSocket('wss://a.example.com')</script>`,
    `${goodGame}<img src="https://cdn.example.com/a.png">`,
    `${goodGame}<script src="//cdn.example.com/lib.js"></script>`,
    `${goodGame}<script>localStorage.setItem('a',1)</script>`,
    `${goodGame}<script>document.cookie='a=1'</script>`,
    `${goodGame}<script>var x=new XMLHttpRequest()</script>`
  ];
  for (const html of bad) {
    const result = await run({ title: 'Bad', html });
    assert.equal(result.success, false, html.slice(-60));
    assert.match(result.error, /no internet and no saved data/);
  }
});

test('an inline SVG namespace is not mistaken for a web address', async () => {
  const svg = `${goodGame}<svg xmlns="http://www.w3.org/2000/svg" width="40" height="40"><circle cx="20" cy="20" r="18"/></svg>`;
  assert.equal((await run({ title: 'Svg', html: svg })).success, true);
});

test('missing, tiny and oversized pages are refused with a reason the model can act on', async () => {
  assert.equal((await run({ title: 'None' })).success, false);
  assert.match((await run({ title: 'Tiny', html: '<p>hi</p>' })).error, /too short/);
  const big = await run({ title: 'Big', html: `<div>${'a'.repeat(61000)}</div>` });
  assert.equal(big.success, false);
  assert.match(big.error, /too long/);
});

test('the title falls back and is bounded', async () => {
  assert.equal((await run({ html: goodGame })).playable.title, 'Game');
  assert.equal((await run({ title: 'x'.repeat(200), html: goodGame })).playable.title.length, 80);
});

test('make_game is a direct, low-risk capability whose guidance covers the box it runs in', () => {
  const contract = getActionContract('make_game');
  assert.equal(contract.executionMode, 'direct');
  assert.equal(contract.risk, 'low');
  assert.match(contract.guidance, /no internet, no saved data/);
  assert.match(contract.guidance, /390 pixel/);
  assert.match(getActionContract('play_game').guidance, /use make_game/);
});
