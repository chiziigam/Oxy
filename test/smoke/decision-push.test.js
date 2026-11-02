const assert = require('node:assert/strict');
const test = require('node:test');
const { buildDecisionPush, buildApprovalPush, buildResultPush, categoryFor, announce } = require('../../api/services/decision-push');

const workflow = { id: 'wf1', goal: 'Book the plumber' };
const checkpoint = (over = {}) => ({ id: 'cp1', type: 'approval', prompt: 'Book the plumber for Thursday at 2pm?', options: null, ...over });

test('a plain approval can be answered from the lock screen', () => {
  assert.equal(buildDecisionPush({ checkpoint: checkpoint(), workflow }).category, 'adam.approve');
});

test('an empty options list is still a plain approval', () => {
  assert.equal(buildDecisionPush({ checkpoint: checkpoint({ options: [] }), workflow }).category, 'adam.approve');
});

test('a payment with an amount needs unlock and shows the amount in the body', () => {
  const push = buildDecisionPush({ checkpoint: checkpoint({ type: 'payment_confirmation', prompt: 'Pay £8.40 to Tesco for the groceries?' }), workflow });
  assert.equal(push.category, 'adam.approve.unlock');
  assert.match(push.body, /£8\.40/);
});

test('a payment whose amount cannot be read opens the app instead of offering a one-tap approve', () => {
  const push = buildDecisionPush({ checkpoint: checkpoint({ type: 'payment_confirmation', prompt: 'Pay the invoice?' }), workflow });
  assert.equal(push.category, 'adam.choose');
});

test('a legal confirmation needs unlock', () => {
  assert.equal(buildDecisionPush({ checkpoint: checkpoint({ type: 'legal_confirmation', prompt: 'Submit the declaration?' }), workflow }).category, 'adam.approve.unlock');
});

test('a choice between options opens the app', () => {
  const options = [{ id: 'a', label: 'Thursday' }, { id: 'b', label: 'Friday' }];
  assert.equal(buildDecisionPush({ checkpoint: checkpoint({ type: 'choice_required', options }), workflow }).category, 'adam.choose');
});

test('missing information and sign-in requests open the app and never ask for a secret in a notification', () => {
  for (const type of ['missing_information', 'authentication_required']) {
    assert.equal(buildDecisionPush({ checkpoint: checkpoint({ type }), workflow }).category, 'adam.choose');
  }
});

test('the push is keyed to its checkpoint so a repeat replaces it', () => {
  const push = buildDecisionPush({ checkpoint: checkpoint(), workflow });
  assert.equal(push.collapseId, 'cp1');
  assert.equal(push.threadId, 'wf1');
  assert.deepEqual(push.data, { workflowId: 'wf1', checkpointId: 'cp1' });
});

test('the body is plain text and bounded', () => {
  const push = buildDecisionPush({ checkpoint: checkpoint({ prompt: `Line one\n\u0007${'x'.repeat(400)}` }), workflow });
  assert.ok(push.body.length <= 240);
  assert.doesNotMatch(push.body, /[\u0000-\u001f]/);
});

test('categoryFor falls back to opening the app for an unknown type', () => {
  assert.equal(categoryFor({ type: 'something_new', options: null, hasAmount: false }), 'adam.choose');
});

const approval = (action, over = {}) => ({ approvalId: 'ap1', taskId: 't1', action, ...over });

test('a parked email send needs unlock and names who it goes to', () => {
  const push = buildApprovalPush({ approval: approval({ type: 'send_email', input: { to: 'sam@example.com', subject: 'Saturday' } }), risk: 'high' });
  assert.equal(push.category, 'adam.approve.unlock');
  assert.match(push.body, /sam@example\.com/);
  assert.deepEqual(push.data, { approvalId: 'ap1', taskId: 't1' });
  assert.equal(push.collapseId, 'ap1');
});

test('a low-risk parked action can be approved without unlock', () => {
  const push = buildApprovalPush({ approval: approval({ type: 'create_task', input: { title: 'Call the vet' } }), risk: 'low' });
  assert.equal(push.category, 'adam.approve');
});

test('a parked spend shows its amount and needs unlock', () => {
  const push = buildApprovalPush({ approval: approval({ type: 'transaction_authorize', input: { amount: 8.4, currency: 'GBP', merchant: 'Tesco' } }), risk: 'high' });
  assert.equal(push.category, 'adam.approve.unlock');
  assert.match(push.body, /£8\.40/);
});

test('a parked spend with no readable amount opens the app', () => {
  const push = buildApprovalPush({ approval: approval({ type: 'transaction_authorize', input: { merchant: 'Tesco' } }), risk: 'high' });
  assert.equal(push.category, 'adam.choose');
});

test('announce raises one event carrying the push actions, then delivers', async () => {
  const calls = [];
  const delivery = {
    raise: async (userId, event) => { calls.push(['raise', userId, event]); return { ok: true }; },
    deliverPending: async (userId) => { calls.push(['deliver', userId]); }
  };
  const push = buildDecisionPush({ checkpoint: checkpoint(), workflow });
  const result = await announce({ delivery, userId: 'u1', push });
  assert.equal(result.ok, true);
  assert.equal(calls[0][2].dedupeKey, 'action_required|decision:cp1');
  assert.deepEqual(calls[0][2].sourceRef.push, { apsCategory: 'adam.approve', threadId: 'wf1', collapseId: 'cp1', data: { workflowId: 'wf1', checkpointId: 'cp1' } });
  assert.deepEqual(calls[1], ['deliver', 'u1']);
});

test('announce never throws, so a failed push cannot fail the decision', async () => {
  const delivery = { raise: async () => { throw new Error('db down'); }, deliverPending: async () => {} };
  const result = await announce({ delivery, userId: 'u1', push: buildDecisionPush({ checkpoint: checkpoint(), workflow }) });
  assert.equal(result.ok, false);
});

test('a finished piece of work pushes its result with a See it action', () => {
  const push = buildResultPush({ workflow: { id: 'wf1', goal: 'Find flights to Lisbon', status: 'completed', current_step: 'Found 3 flights under £120' } });
  assert.equal(push.category, 'adam.result');
  assert.equal(push.title, 'Find flights to Lisbon');
  assert.equal(push.body, 'Found 3 flights under £120');
  assert.equal(push.collapseId, 'wf1');
  assert.deepEqual(push.data, { workflowId: 'wf1' });
});

test('failed work says it could not finish', () => {
  const push = buildResultPush({ workflow: { id: 'wf1', goal: 'Pay the water bill', status: 'failed', current_step: 'The site was down' } });
  assert.equal(push.body, 'Could not finish. The site was down');
});

test('work that is still going or was cancelled pushes nothing', () => {
  for (const status of ['working', 'gathering', 'cancelled', 'waiting_for_user']) {
    assert.equal(buildResultPush({ workflow: { id: 'wf1', goal: 'x', status } }), null);
  }
});
