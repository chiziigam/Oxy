const assert = require('node:assert/strict');
const test = require('node:test');

const stocks = require('../../connectors/stocks');
const brainProvider = require('../../api/services/brain-provider');

const QUOTE = {
  symbol: 'AAPL',
  exchange: 'NasdaqGS',
  price: 353.32,
  previousClose: 331.9,
  currency: 'USD',
  at: new Date(Date.UTC(2026, 10, 4, 19, 0))
};

test('a quote reads as one plain sentence with the day it moved', () => {
  const text = stocks.formatQuote(QUOTE);
  assert.equal(text, 'AAPL on NasdaqGS: $353.32, up 6.5% today as of 19:00 GMT. Quotes may be delayed.');
});

test('a fall is described as a fall, and its size is never negative', () => {
  const text = stocks.formatQuote({ ...QUOTE, price: 300, previousClose: 310 });
  assert.match(text, /down 3\.2% today/);
});

test('a quote with no previous close says nothing it cannot support', () => {
  const text = stocks.formatQuote({ ...QUOTE, previousClose: undefined });
  assert.match(text, /^\$?AAPL on NasdaqGS: \$353\.32 as of/);
  assert.doesNotMatch(text, /today/);
});

test('symbols are normalised the way the quote endpoint expects', () => {
  assert.equal(stocks.normaliseSymbol(' aapl '), 'AAPL');
  assert.equal(stocks.normaliseSymbol('brk b'), 'BRKB');
});

test('other currencies are not dressed up as dollars', () => {
  assert.match(stocks.formatQuote({ ...QUOTE, currency: 'GBP', price: 12.5 }), /£12\.50/);
  assert.match(stocks.formatQuote({ ...QUOTE, currency: 'SEK', price: 12.5 }), /12\.50 SEK/);
});

test('a live quote is used when the endpoint answers, without any web search', async () => {
  const savedFetch = global.fetch;
  const savedSearch = brainProvider.webSearchBrain;
  global.fetch = async () => ({
    ok: true,
    json: async () => ({
      chart: {
        result: [{
          meta: {
            symbol: 'AAPL', fullExchangeName: 'NasdaqGS', currency: 'USD',
            regularMarketPrice: 353.32, chartPreviousClose: 331.9, regularMarketTime: 1793820038
          }
        }]
      }
    })
  });
  brainProvider.webSearchBrain = async () => { throw new Error('the search must not be used'); };
  try {
    const result = await stocks.execute('u1', 'get_stock_price', { symbol: 'aapl' });
    assert.equal(result.source, 'yahoo-finance');
    assert.match(result.text, /\$353\.32/);
  } finally {
    global.fetch = savedFetch;
    brainProvider.webSearchBrain = savedSearch;
  }
});

test('an unresolvable symbol falls back to the grounded search', async () => {
  const savedFetch = global.fetch;
  const savedSearch = brainProvider.webSearchBrain;
  global.fetch = async () => ({ ok: false, status: 404 });
  brainProvider.webSearchBrain = async () => 'Nothing quotable for that listing.';
  try {
    const result = await stocks.execute('u1', 'get_stock_price', { symbol: 'NOTAREALTICKER' });
    assert.equal(result.source, 'grounded_web_search');
    assert.match(result.text, /Nothing quotable/);
  } finally {
    global.fetch = savedFetch;
    brainProvider.webSearchBrain = savedSearch;
  }
});
