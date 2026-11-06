'use strict';

const { createActionSelection } = require('../services/action-selection');
const playSessions = require('../services/play-sessions');

function guessSelection(result) {
  const options = Array.from({ length: playSessions.GUESS_MAX }, (_, i) => ({
    id: `n${i + 1}`,
    label: String(i + 1),
    command: `choose option ${i + 1}`,
    input: { guess: String(i + 1) }
  }));
  return createActionSelection({ actionType: 'play_game', actionInput: result.receipt, options });
}

function selectionFor(result) {
  if (result?.finished) {
    return createActionSelection({
      actionType: 'play_game',
      actionInput: { game: result.game || 'trivia', operation: 'start' },
      options: [{
        id: 'rematch',
        label: 'Play again',
        command: 'play again',
        input: {}
      }]
    });
  }
  if (result?.game === 'guess' && result.receipt) return guessSelection(result);
  if (!result?.question || !result.receipt) return null;
  return createActionSelection({
    actionType: 'play_game',
    actionInput: result.receipt,
    options: result.question.choices.map((choice, index) => ({
      id: choice.id,
      label: choice.label,
      command: `choose option ${index + 1}`,
      input: { choice_id: choice.id }
    }))
  });
}

async function playGame({ params } = {}) {
  const game = String(params?.game || '').trim().toLowerCase();
  if (game !== 'trivia' && game !== 'guess') {
    return { success: false, error: 'I can play trivia or a number guessing game right now.' };
  }

  const operation = String(params?.operation || 'start').trim().toLowerCase();
  let result;
  if (game === 'guess') {
    result = operation === 'answer'
      ? playSessions.answerGuess({ sessionId: params?.session_id, guess: params?.guess, round: params?.round })
      : playSessions.startGuess({ sessionId: params?.session_id });
  } else {
    result = operation === 'answer'
      ? playSessions.answerTrivia({
        sessionId: params?.session_id,
        questionId: params?.question_id,
        choiceId: params?.choice_id,
        round: params?.round,
        score: params?.score
      })
      : playSessions.startTrivia({ sessionId: params?.session_id });
  }
  if (!result.success && result.error) return result;

  const selection = selectionFor(result);
  return {
    success: true,
    text: result.text,
    cardText: result.text,
    actionSummary: result.finished ? 'Game finished' : 'Game in progress',
    ...(selection ? { selection } : {}),
    game,
    sessionId: result.sessionId,
    round: result.round,
    score: result.score,
    finished: result.finished === true
  };
}

module.exports = {
  handlers: {
    play_game: playGame
  }
};
