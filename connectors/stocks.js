const brainProvider = require('../api/services/brain-provider');
const { defaultModelForProvider } = require('../api/services/model-routing');

const TIMEOUT_MS = Number(process.env.OXY_STOCKS_TIMEOUT_MS || 5000);
const USER_AGENT = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Oxy/1.0';

const SYMBOLS = { USD: '$', GBP: '£', EUR: '€', JPY: '¥', CAD: 'C$', AUD: 'A$', CHF: 'CHF ', HKD: 'HK$', INR: '₹' };

function money(amount, currency) {
  if (!Number.isFinite(amount)) return null;
  const symbol = SYMBOLS[String(currency || '').toUpperCase()];
  const value = Math.abs(amount) >= 1000 ? amount.toFixed(0) : amount.toFixed(2);
  return symbol ? `${symbol}${value}` : `${value} ${String(currency || '').toUpperCase()}`.trim();
}

function formatQuote({ symbol, exchange, price, previousClose, currency, at }) {
  if (!Number.isFinite(price)) return null;
  const parts = [money(price, currency)];
  if (Number.isFinite(previousClose) && previousClose > 0) {
    const change = price - previousClose;
    const percent = Math.abs(change / previousClose) * 100;
    const direction = change >= 0 ? 'up' : 'down';
    parts.push(`${direction} ${percent.toFixed(1)}% today`);
  }
  const when = at ? ` as of ${at.toISOString().slice(11, 16)} GMT` : '';
  const where = exchange ? ` on ${exchange}` : '';
  return `${String(symbol || '').toUpperCase()}${where}: ${parts.join(', ')}${when}. Quotes may be delayed.`;
}

function normaliseSymbol(raw) {
  return String(raw || '').trim().toUpperCase().replace(/\s+/g, '');
}

async function quoteFor(symbol) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), TIMEOUT_MS);
  try {
    const url = `https://query1.finance.yahoo.com/v8/finance/chart/${encodeURIComponent(symbol)}?range=1d&interval=1m`;
    const res = await fetch(url, { headers: { 'User-Agent': USER_AGENT }, signal: controller.signal });
    if (!res.ok) throw new Error(`quote lookup ${res.status}`);
    const json = await res.json();
    const meta = json?.chart?.result?.[0]?.meta;
    if (!meta || !Number.isFinite(meta.regularMarketPrice)) throw new Error('no quote in the response');
    return {
      symbol: meta.symbol || symbol,
      exchange: meta.fullExchangeName || meta.exchangeName || null,
      price: meta.regularMarketPrice,
      previousClose: Number.isFinite(meta.chartPreviousClose) ? meta.chartPreviousClose : meta.previousClose,
      currency: meta.currency || null,
      at: Number.isFinite(meta.regularMarketTime) ? new Date(meta.regularMarketTime * 1000) : null
    };
  } finally {
    clearTimeout(timeout);
  }
}

async function liveQuote(symbol) {
  const quote = await quoteFor(normaliseSymbol(symbol));
  const text = formatQuote(quote);
  if (!text) throw new Error('quote could not be read');
  return { success: true, outcome: 'completed', text, symbol: quote.symbol, source: 'yahoo-finance' };
}

function searchModel() {
  return defaultModelForProvider(process.env.OXY_BRAIN_PROVIDER || 'openai', 'fast');
}

// Kept as the fallback: it answers "what is this company" and copes with a name the quote
// endpoint cannot resolve, so the capability never disappears.
async function groundedStockSearch(symbol, search = false) {
  const today = new Date().toISOString().slice(0, 10);
  const prompt = search
    ? `Today's date is ${today}. Search the web for the publicly traded company or stock symbol ${symbol}. Return the best-supported current listing details and exchange, and distinguish an identity result from a live quote. Do not invent a price. Plain concise text.`
    : `Today's date is ${today}. Search the web for the current stock quote for ${symbol}. Return the current price, currency, daily change or percentage where available, whether the quote is delayed or the market is closed, and the quote time. Do not invent a price; say plainly if no current quote is supported. Plain concise text.`;
  const text = await brainProvider.webSearchBrain({ model: searchModel(), prompt });
  if (!text) {
    return {
      success: false,
      outcome: 'unavailable',
      unavailable: true,
      error: `No grounded stock result was available for ${symbol}.`
    };
  }
  return { success: true, outcome: 'completed', text, symbol, source: 'grounded_web_search' };
}

async function execute(userId, action, params) {
  const symbol = params.symbol || params.query || 'AAPL';
  try {
    if (action === 'get_stock_price') {
      try {
        return await liveQuote(symbol);
      } catch {
        // No usable quote for this symbol; the grounded search may still know it.
      }
      return await groundedStockSearch(symbol);
    }
    if (action === 'search_stocks') {
      return await groundedStockSearch(symbol, true);
    }
    return { success: false, outcome: 'failed', error: 'Unknown stocks action' };
  } catch (e) {
    return { success: false, outcome: 'failed', error: `Stock search failed: ${e.message}` };
  }
}

module.exports = { execute, formatQuote, normaliseSymbol, money };
