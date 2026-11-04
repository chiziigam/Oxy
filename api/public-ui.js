'use strict';

const fs = require('fs');
const path = require('path');

const CSS = fs.readFileSync(path.join(__dirname, '..', 'web-design-tokens.css'), 'utf8');

function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

function page({ title, body, card = false }) {
  return `<!doctype html>
<html lang="en-GB">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="color-scheme" content="light dark">
  <title>${escapeHtml(title)} · Adam</title>
  <style>${CSS}</style>
</head>
<body>
  <a class="skip" href="#content">Skip to content</a>
  <header class="top">
    <a class="word" href="/">Adam</a>
    <nav aria-label="Site">
      <a href="/support">Support</a>
      <a href="/privacy">Privacy</a>
      <a href="/terms">Terms</a>
    </nav>
  </header>
  <main id="content"${card ? ' class="card"' : ''}>${body}</main>
</body>
</html>`;
}

module.exports = { page, escapeHtml };
