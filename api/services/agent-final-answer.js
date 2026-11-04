'use strict';

// After several steps, a model sometimes finishes by repeating one tool's stock status line
// ("Walking directions to X are ready.") instead of answering. That line carries no answer.

function normalise(text) {
  return String(text || '').toLowerCase().replace(/[*_`#>\[\]()]/g, ' ').replace(/[^a-z0-9£$€%.:\s]/g, ' ').replace(/\s+/g, ' ').trim();
}

function isEchoOfToolText(spoken, executedActions) {
  const said = normalise(spoken);
  if (!said || said.length > 220 || !Array.isArray(executedActions) || executedActions.length < 2) return false;
  return executedActions.some((entry) => {
    const stock = normalise(entry?.result?.text);
    if (stock.length < 15) return false;
    return said === stock || (said.length <= stock.length + 20 && (said.includes(stock) || stock.includes(said)));
  });
}

const WRITE_UP_PROMPT = 'That line is only a status message from one tool. Using all the results above, answer my original request properly in a few plain sentences, with the specific facts and numbers I asked for.';

// A browser step's observation (page title and URL, the numbered control list, the page text) is
// for the model only. These markers are what that observation looks like in text.
const OBSERVATION_MARKERS = [
  /Controls on this page \(use the number as elementId\):/i,
  /No interactive controls found on this page\./i,
  /use the number as elementId/i,
];
// Element lines: #12 "Add to basket" or #3 [dropdown, options: "A", "B"] "Size".
const ELEMENT_LINE = /^\s*#\d+(\s+\[(input|dropdown[^\]]*)\])?\s+".*"\s*$/;

function elementLineCount(text) {
  return String(text || '').split('\n').filter((line) => ELEMENT_LINE.test(line)).length;
}

function isToolObservation(text) {
  const value = String(text || '');
  if (!value.trim()) return false;
  return OBSERVATION_MARKERS.some((re) => re.test(value)) || elementLineCount(value) >= 3;
}

// The same browser observation, as a result object (see observationResult in actions/browser.js).
function isObservationResult(result) {
  return Boolean(result && typeof result === 'object'
    && (Array.isArray(result.elements) || 'pageTitle' in result || 'pageText' in result)
    && isToolObservation(result.text));
}

// Removes an observation dump from text meant for the user: the control list, element lines,
// the "Page text:" block and a leading "Title — https://…" line. Plain sentences around it stay.
function stripToolObservation(text) {
  const value = String(text || '');
  if (!isToolObservation(value)) return value;
  const kept = [];
  let skipping = false;
  for (const line of value.split('\n')) {
    const trimmed = line.trim();
    if (OBSERVATION_MARKERS.some((re) => re.test(trimmed)) || /^Page text:/i.test(trimmed)) { skipping = true; continue; }
    if (ELEMENT_LINE.test(line)) { skipping = true; continue; }
    if (/^.{0,200}\s[—-]\s+https?:\/\/\S+\s*$/.test(trimmed)) continue;
    if (skipping && trimmed === '') { skipping = false; continue; }
    if (skipping) continue;
    kept.push(line);
  }
  return kept.join('\n').replace(/\n{3,}/g, '\n\n').trim();
}

const PLAIN_ANSWER_PROMPT = 'That reply showed me the raw page you opened, which is only for you. Answer my original request in one or two plain sentences with the specific facts I asked for (for example: "Yes, John Lewis has Call of Duty: Modern Warfare 4 for PS5 at £59.99."), and include at most one link. Do not list page controls, element numbers or page text.';

const OBSERVATION_FALLBACK = "I opened the page but couldn't read a clear answer from it. Want me to look again?";

// The last line of defence before a reply reaches the user: never let an observation through.
function sanitizeReply(text) {
  if (!isToolObservation(text)) return text;
  const stripped = stripToolObservation(text);
  return stripped.length >= 20 ? stripped : OBSERVATION_FALLBACK;
}

module.exports = {
  isEchoOfToolText,
  WRITE_UP_PROMPT,
  isToolObservation,
  isObservationResult,
  stripToolObservation,
  sanitizeReply,
  PLAIN_ANSWER_PROMPT,
  OBSERVATION_FALLBACK,
};
