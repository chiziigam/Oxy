'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');

const { handlers } = require('../../api/actions/play');
const { MAX_ROUNDS, QUESTIONS } = require('../../api/services/play-sessions');
const { resolveContextualTurn } = require('../../api/services/context-brain');

test('starting trivia creates a bounded question with an exact answer selection', async () => {
  const result = await handlers.play_game({
    params: { game: 'trivia' },
    context: {}
  });

  assert.equal(result.success, true);
  assert.match(result.text, /1\./);
  assert.match(result.text, /2\./);
  assert.match(result.text, /3\./);
  assert.equal(result.selection.action.type, 'play_game');
  assert.equal(result.selection.action.input.operation, 'answer');
  assert.ok(result.selection.action.input.question_id);
  assert.equal(result.selection.options.length, 3);
  assert.equal(result.selection.options[0].input.choice_id, result.selection.options[0].id);
});

test('a natural numbered answer resolves to the exact play action and advances the session', async () => {
  const first = await handlers.play_game({ params: { game: 'trivia' }, context: {} });
  const history = [{
    role: 'assistant',
    content: first.text,
    actions: [{ action: 'play_game', result: first }]
  }];
  const resolved = resolveContextualTurn({ message: 'the first one', history, recentActions: [] });

  assert.equal(resolved.reason, 'context_selection_selected');
  const second = await handlers.play_game({ params: resolved.actions[0].input, context: {} });
  assert.equal(second.success, true);
  assert.match(second.text, /Round 2/);
  assert.notEqual(second.selection.action.input.question_id, first.selection.action.input.question_id);
});

test('a spoken answer that repeats the visible choice resolves without requiring an ordinal', async () => {
  const first = await handlers.play_game({ params: { game: 'trivia' }, context: {} });
  const history = [{
    role: 'assistant',
    content: first.text,
    actions: [{ action: 'play_game', result: first }]
  }];
  const spokenAnswer = first.selection.options[0].label.toLowerCase();
  const resolved = resolveContextualTurn({ message: spokenAnswer, history, recentActions: [] });

  assert.equal(resolved.reason, 'context_selection_selected');
  assert.equal(resolved.actions[0].input.choice_id, first.selection.options[0].id);
});

test('finishing trivia offers a fresh one-tap rematch', async () => {
  let turn = await handlers.play_game({ params: { game: 'trivia' }, context: {} });
  const firstSessionId = turn.sessionId;

  for (let round = 1; round <= MAX_ROUNDS; round += 1) {
    const question = QUESTIONS.find(candidate => candidate.id === turn.selection.action.input.question_id);
    turn = await handlers.play_game({
      params: { ...turn.selection.action.input, choice_id: question.answer },
      context: {}
    });
  }

  assert.equal(turn.finished, true);
  assert.equal(turn.selection.action.type, 'play_game');
  assert.equal(turn.selection.action.input.operation, 'start');

  const resolved = resolveContextualTurn({
    message: 'play again',
    history: [{ role: 'assistant', content: turn.text, actions: [{ action: 'play_game', result: turn }] }],
    recentActions: []
  });
  assert.equal(resolved.reason, 'context_selection_selected');
  const rematch = await handlers.play_game({ params: resolved.actions[0].input, context: {} });
  assert.equal(rematch.finished, false);
  assert.match(rematch.text, /Round 1 of 5/);
  assert.notEqual(rematch.sessionId, firstSessionId);
});

test('trivia refuses unknown games and malformed answers without pretending a turn happened', async () => {
  const unknown = await handlers.play_game({ params: { game: 'roulette' }, context: {} });
  assert.equal(unknown.success, false);

  const malformed = await handlers.play_game({
    params: { game: 'trivia', operation: 'answer', session_id: 'session-1', question_id: 'missing', choice_id: '1' },
    context: {}
  });
  assert.equal(malformed.success, false);
});

test('the guessing game keeps its number on the server and never puts it in a result', async () => {
  const start = await handlers.play_game({ params: { game: 'guess' }, context: {} });
  assert.equal(start.success, true);
  assert.match(start.text, /number from 1 to 8/);
  assert.equal(start.selection.options.length, 8);
  assert.equal(start.selection.action.input.operation, 'answer');
  assert.equal(start.selection.action.input.session_id, start.sessionId);

  const { secretCandidates } = await findSecret(start.sessionId);
  assert.equal(secretCandidates.length, 1, 'exactly one guess wins');
  assert.doesNotMatch(JSON.stringify(start), /secret|correct|"won"/i, 'nothing marks the number');
});

async function findSecret(sessionId) {
  const winners = [];
  for (let guess = 1; guess <= 8; guess += 1) {
    const turn = await handlers.play_game({
      params: { game: 'guess', operation: 'answer', session_id: sessionId, round: 1, guess },
      context: {}
    });
    if (turn.finished && /^Yes/.test(turn.text)) winners.push(guess);
  }
  return { secretCandidates: winners };
}

test('a wrong guess gets a true hint and a right one ends the game', async () => {
  const start = await handlers.play_game({ params: { game: 'guess' }, context: {} });
  const [secret] = (await findSecret(start.sessionId)).secretCandidates;
  const wrong = secret === 1 ? 2 : 1;
  const hint = await handlers.play_game({
    params: { game: 'guess', operation: 'answer', session_id: start.sessionId, round: 1, guess: wrong },
    context: {}
  });
  assert.equal(hint.success, true);
  assert.equal(hint.finished, false);
  assert.match(hint.text, wrong < secret ? /Too low/ : /Too high/);
  assert.match(hint.text, /Guess 2 of 3/);
  assert.equal(hint.selection.action.input.round, 2);

  const win = await handlers.play_game({
    params: { game: 'guess', operation: 'answer', session_id: start.sessionId, round: 2, guess: secret },
    context: {}
  });
  assert.equal(win.finished, true);
  assert.match(win.text, new RegExp(`it was ${secret}\\. You got it in 2 guesses`));
  assert.equal(win.selection.options[0].label, 'Play again');
});

test('three wrong guesses reveal the number and offer another go at the same game', async () => {
  const start = await handlers.play_game({ params: { game: 'guess' }, context: {} });
  const [secret] = (await findSecret(start.sessionId)).secretCandidates;
  const wrong = secret === 1 ? 2 : 1;
  const out = await handlers.play_game({
    params: { game: 'guess', operation: 'answer', session_id: start.sessionId, round: 3, guess: wrong },
    context: {}
  });
  assert.equal(out.finished, true);
  assert.match(out.text, new RegExp(`Out of guesses\\. It was ${secret}\\.`));
  assert.equal(out.selection.action.input.game, 'guess');
});

test('different sessions get different numbers over a run, and a bad guess is refused', async () => {
  const seen = new Set();
  for (let i = 0; i < 12; i += 1) {
    const start = await handlers.play_game({ params: { game: 'guess' }, context: {} });
    seen.add((await findSecret(start.sessionId)).secretCandidates[0]);
  }
  assert.ok(seen.size > 1, 'the number is not fixed');
  const bad = await handlers.play_game({
    params: { game: 'guess', operation: 'answer', session_id: 'abc', round: 1, guess: 99 },
    context: {}
  });
  assert.equal(bad.success, false);
  const unknown = await handlers.play_game({ params: { game: 'chess' }, context: {} });
  assert.equal(unknown.success, false);
  assert.match(unknown.error, /trivia or a number guessing game/);
});

test('the guessing game guidance says not to claim a hidden number and not to run code', () => {
  const { getActionContract } = require('../../api/action-contracts');
  const guidance = getActionContract('play_game').guidance;
  assert.match(guidance, /Never say you have picked a secret number/);
  assert.match(guidance, /CODE for a game/);
});
