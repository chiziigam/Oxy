const test = require('node:test');
const assert = require('node:assert');
const { isPendingConfirmMessage, isPendingCancelMessage, isPendingRevisionMessage } = require('../../api/services/pending-review');

test('short replies to a waiting approval are still recognised', () => {
  assert.strictEqual(isPendingConfirmMessage('yes'), true);
  assert.strictEqual(isPendingConfirmMessage('go ahead'), true);
  assert.strictEqual(isPendingCancelMessage('cancel it'), true);
  assert.strictEqual(isPendingRevisionMessage('make it shorter'), true);
  assert.strictEqual(isPendingRevisionMessage('actually change the time to 5'), true);
});

test('an unrelated sentence containing "confirmed" or "stop" does not act on a waiting approval', () => {
  assert.strictEqual(isPendingConfirmMessage('my appointment was confirmed by the clinic'), false);
  assert.strictEqual(isPendingConfirmMessage('the bank confirmed the transfer went through'), false);
  assert.strictEqual(isPendingCancelMessage('which bus stop is near the station'), false);
  assert.strictEqual(isPendingCancelMessage('where is the nearest stop'), false);
});

test('short imperative yes and no replies still work', () => {
  assert.strictEqual(isPendingConfirmMessage('approve it'), true);
  assert.strictEqual(isPendingConfirmMessage('confirm that'), true);
  assert.strictEqual(isPendingConfirmMessage('yes, send it'), true);
  assert.strictEqual(isPendingConfirmMessage('Yes, confirm.'), true);
  assert.strictEqual(isPendingCancelMessage('cancel it'), true);
  assert.strictEqual(isPendingCancelMessage('stop that'), true);
});

test('a long new request is not mistaken for a reply to a waiting approval', () => {
  const request = "Find the price of the cheapest kettle at Argos. If you can't get it, find the cheapest one at John Lewis instead and tell me which you used.";
  assert.strictEqual(isPendingRevisionMessage(request), false);
  assert.strictEqual(isPendingCancelMessage('Which bus stop is nearest to the Bullring if I am coming from the train station today?'), false);
  assert.strictEqual(isPendingConfirmMessage('Please approve my holiday request form for next week and then book the hotel for two nights in Lisbon too'), false);
});
