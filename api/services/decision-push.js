'use strict';

const UNLOCK_TYPES = new Set(['payment_confirmation', 'legal_confirmation']);
const APPROVE_TYPES = new Set(['approval', 'payment_confirmation', 'legal_confirmation']);
const AMOUNT = /[£$€]\s?\d/;

function plain(value, max) {
  const text = String(value ?? '').replace(/[\u0000-\u001f\u007f]/g, ' ').replace(/\s+/g, ' ').trim();
  return text.length > max ? `${text.slice(0, max - 1)}…` : text;
}

function categoryFor({ type, options, hasAmount }) {
  if (Array.isArray(options) && options.length) return 'adam.choose';
  if (!APPROVE_TYPES.has(type)) return 'adam.choose';
  if (type === 'payment_confirmation' && !hasAmount) return 'adam.choose';
  return UNLOCK_TYPES.has(type) ? 'adam.approve.unlock' : 'adam.approve';
}

function buildDecisionPush({ checkpoint, workflow }) {
  const body = plain(checkpoint.prompt, 240);
  return {
    title: plain(workflow?.goal, 60) || 'Adam',
    body,
    category: categoryFor({ type: checkpoint.type, options: checkpoint.options, hasAmount: AMOUNT.test(body) }),
    threadId: workflow?.id || null,
    collapseId: checkpoint.id,
    data: { workflowId: workflow?.id || null, checkpointId: checkpoint.id }
  };
}

const MONEY_ACTIONS = new Set([
  'transaction_authorize', 'spend_from_concierge_account', 'spend_from_concierge_via_stripe',
  'fund_opportunity', 'stripe_charge', 'stripe_payout_to_user', 'confirm_browser_payment'
]);
const SYMBOLS = { GBP: '£', USD: '$', EUR: '€' };

function amountText(input = {}, body = '') {
  if (AMOUNT.test(body)) return '';
  const value = Number(input.amount ?? input.total);
  if (!Number.isFinite(value) || value <= 0) return '';
  const symbol = SYMBOLS[String(input.currency || 'GBP').toUpperCase()];
  return symbol ? `${symbol}${value.toFixed(2)}` : '';
}

function buildApprovalPush({ approval, risk }) {
  const input = approval?.action?.input || {};
  const type = String(approval?.action?.type || '');
  const detail = plain([input.contact || input.to || input.title || input.destination || input.merchant || input.repo, input.message || input.subject].filter(Boolean).join(' · '), 160);
  const body = plain(detail || approval?.taskGoal || 'Something is waiting for you.', 240);
  const amount = amountText(input, body);
  const shown = amount ? plain(`${amount} ${body}`, 240) : body;
  const money = MONEY_ACTIONS.has(type);
  let category = risk === 'high' ? 'adam.approve.unlock' : 'adam.approve';
  if (money && !(amount || AMOUNT.test(body))) category = 'adam.choose';
  return {
    title: 'Needs a yes',
    body: shown,
    category,
    threadId: approval?.taskId || null,
    collapseId: approval?.approvalId,
    data: { approvalId: approval?.approvalId, taskId: approval?.taskId || null }
  };
}

function buildResultPush({ workflow }) {
  const status = workflow?.status;
  if (status !== 'completed' && status !== 'failed') return null;
  const detail = plain(workflow.current_step || workflow.next_action, 200);
  const body = status === 'failed' ? plain(`Could not finish. ${detail}`, 240) : detail || 'Done.';
  return {
    title: plain(workflow.goal, 60) || 'Adam',
    body,
    category: 'adam.result',
    threadId: workflow.id,
    collapseId: workflow.id,
    data: { workflowId: workflow.id }
  };
}

async function announce({ delivery, userId, push, category = 'action_required' }) {
  try {
    const queued = await delivery.raise(userId, {
      category,
      urgency: 'normal',
      title: push.title,
      body: push.body,
      dedupeKey: `${category}|decision:${push.collapseId}`,
      sourceRef: { push: { apsCategory: push.category, threadId: push.threadId, collapseId: push.collapseId, data: push.data } }
    });
    if (!queued?.ok) return { ok: false, error: queued?.error || 'not raised' };
    await delivery.deliverPending(userId);
    return { ok: true };
  } catch (error) {
    return { ok: false, error: error.message };
  }
}

module.exports = { buildDecisionPush, buildApprovalPush, buildResultPush, categoryFor, announce };
