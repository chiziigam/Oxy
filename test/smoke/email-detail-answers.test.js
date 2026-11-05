const assert = require('node:assert/strict');
const test = require('node:test');

const { isEmailDetailRequest, buildStructuredDataSummary } = require('../../api/index');

const ticketBody = [
  'Your tickets are issued.',
  'Birmingham New Street to Staines.',
  'Depart 08:03 Birmingham New Street. Change at Reading. Arrive Staines 10:56. Stay on the train at Banbury.',
  'Collection code 7Q4K2X.'
].join('\n');

const ticketEmail = {
  from: 'TrainPal <no-reply@trainpal.com>',
  subject: 'Your booking is confirmed',
  date: 'Wed, 5 Nov 2026 09:00:00 +0000',
  snippet: 'Your tickets are issued. Birmingham New Street to',
  body: ticketBody
};
const other = { from: 'Indeed <alert@indeed.com>', subject: '12 new jobs', snippet: 'Recommended jobs.', body: 'Recommended jobs for you.' };

const entry = (emails) => ({ action: 'search_emails', input: { query: 'trainpal' }, result: { success: true, emails } });

test('questions about what an email says are detail requests; inbox checks are not', () => {
  for (const q of ['i got my ticket to staines when do i arrive there tho', 'did you read the email', 'So read it ?', 'what does the email say', 'what is my collection code']) {
    assert.equal(isEmailDetailRequest(q), true, q);
  }
  for (const q of ['check my emails for anything important today', 'hello', 'what did i miss']) {
    assert.equal(isEmailDetailRequest(q), false, q);
  }
});

test('a detail question gives the model the full email text, not the short preview', () => {
  const summary = buildStructuredDataSummary(entry([other, ticketEmail]), 'i got my ticket to staines when do i arrive there tho');
  assert.match(summary.text, /Arrive Staines 10:56/);
  assert.match(summary.text, /Change at Reading/);
  assert.match(summary.text, /Collection code 7Q4K2X/);
  assert.match(summary.text, /full text of the email, not a preview/);
  assert.equal(summary.items[0].subject, 'Your booking is confirmed');
});

test('a long email is cut at the limit and marked truncated', () => {
  const long = { ...ticketEmail, body: `${ticketBody} ${'filler '.repeat(1000)}` };
  const summary = buildStructuredDataSummary(entry([long]), 'when do i arrive');
  assert.match(summary.text, /\[truncated\]/);
  assert.ok(summary.text.length < 3400);
});

test('an email with no body says only a preview was available', () => {
  const summary = buildStructuredDataSummary(entry([{ ...ticketEmail, body: '' }]), 'when do i arrive');
  assert.match(summary.text, /Only a short preview was available/);
});

test('a broad inbox check still uses the short triage summary', () => {
  const summary = buildStructuredDataSummary(entry([other, ticketEmail]), 'check my emails for anything important today');
  assert.match(summary.text, /Email triage/);
  assert.doesNotMatch(summary.text, /Collection code 7Q4K2X/);
});
