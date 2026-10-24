// Vault Manager price service (Cloudflare Worker).
// Cron triggers poll the providers and store one combined quote in KV.
// Every game client reads GET /prices, so one set of API keys and rate limits covers all players.
// Clients ask only every few hours and animate the moves in between themselves.
//
// Response:
// {
//   "prices": { "XAU": 4473.37, "XAG": 73.31, "XPT": 1879.64, "XPD": 1520.0 },   // USD per troy oz
//   "metals_change": { "XAU": -1.2, ... },                                       // % change over about a day
//   "crypto": { "BTC": { "price": 0, "change_pct": 0 }, ... },                   // USD, 24h change
//   "stocks": { "SPY": { "price": 0, "change_pct": 0 }, ... },                   // USD, change since last close
//   "fx": { "EUR": 0.92, "GBP": 0.79, ... },                                     // units per 1 USD
//   "updated": { "metals": "<ISO>", "crypto": "<ISO>", "stocks": "<ISO>", "fx": "<ISO>" }
// }

const METALS = ["XAU", "XAG", "XPT", "XPD"];
const CRYPTO = { BTC: "bitcoin", ETH: "ethereum", SOL: "solana", DOGE: "dogecoin" };
const STOCKS = ["SPY", "AAPL", "NVDA", "TSLA"];

// Metals are rationed by the MetalCharts free tier (about 200 calls a month), so they
// refresh on the slow cron. Crypto, stocks and exchange rates refresh on the fast one.
const SLOW_CRON = "0 */4 * * *";

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname !== "/prices") return new Response("Not found", { status: 404 });
    let body = await env.PRICES.get("latest");
    if (!body) body = JSON.stringify(await refresh(env, "all"));
    return new Response(body, {
      headers: { "content-type": "application/json", "access-control-allow-origin": "*", "cache-control": "max-age=60" },
    });
  },
  async scheduled(event, env) {
    await refresh(env, event.cron === SLOW_CRON ? "slow" : "fast");
  },
};

// mode: "fast" (crypto, stocks), "slow" (metals, exchange rates) or "all".
async function refresh(env, mode) {
  const quote = JSON.parse((await env.PRICES.get("latest")) || "{}");
  quote.updated ||= {};
  const now = new Date().toISOString();
  // Each source fails on its own: a provider outage keeps that section's last values.
  const jobs = [];
  if (mode !== "slow") jobs.push(["crypto", () => fetchCrypto(env)], ["stocks", () => fetchStocks(env)]);
  if (mode !== "fast") jobs.push(["prices", () => fetchMetals(env)], ["fx", fetchFx]);
  for (const [key, job] of jobs) {
    try {
      const data = await job();
      if (Object.keys(data).length) {
        quote[key] = { ...(quote[key] || {}), ...data };
        quote.updated[key === "prices" ? "metals" : key] = now;
      }
    } catch (err) {
      console.log(`${key} refresh failed: ${err.message}`);
    }
  }
  if (quote.updated.metals === now) trackMetalsChange(quote, now);
  await env.PRICES.put("latest", JSON.stringify(quote));
  return quote;
}

// The metals API has no daily change, so keep the last day and a half of metal quotes
// and compare with the newest one that is at least 20 hours old. Drives in-game market events.
function trackMetalsChange(quote, now) {
  const t = Date.parse(now);
  const history = (quote.metals_history || []).filter((s) => t - Date.parse(s.t) < 36 * 3600e3);
  history.push({ t: now, ...quote.prices });
  quote.metals_history = history;
  const old = history.filter((s) => t - Date.parse(s.t) >= 20 * 3600e3).pop();
  if (!old) return;
  quote.metals_change = {};
  for (const m of METALS) {
    if (old[m] > 0 && quote.prices[m] > 0) quote.metals_change[m] = Math.round((quote.prices[m] / old[m] - 1) * 10000) / 100;
  }
}

async function getJson(url, headers = {}) {
  const res = await fetch(url, { headers });
  if (!res.ok) throw new Error(`${new URL(url).host} returned ${res.status}`);
  return res.json();
}

// MetalCharts nests each metal under data.<SYMBOL>. The exact field holding the USD price
// is not confirmed yet, so accept the common spellings until one real call is checked.
async function fetchMetals(env) {
  const raw = await getJson("https://api.metalcharts.org/v1/prices", { Authorization: `Bearer ${env.METALCHARTS_KEY}` });
  const out = {};
  for (const m of METALS) {
    const v = raw?.data?.[m];
    const price = typeof v === "number" ? v : v?.price ?? v?.usd ?? v?.value ?? v?.spot;
    if (typeof price === "number") out[m] = price;
  }
  return out;
}

// CoinGecko demo plan (free key, sent as x-cg-demo-api-key).
async function fetchCrypto(env) {
  const ids = Object.values(CRYPTO).join(",");
  const headers = env.COINGECKO_KEY ? { "x-cg-demo-api-key": env.COINGECKO_KEY } : {};
  const raw = await getJson(`https://api.coingecko.com/api/v3/simple/price?ids=${ids}&vs_currencies=usd&include_24hr_change=true`, headers);
  const out = {};
  for (const [sym, id] of Object.entries(CRYPTO)) {
    const v = raw[id];
    if (v && typeof v.usd === "number") out[sym] = { price: v.usd, change_pct: v.usd_24h_change ?? 0 };
  }
  return out;
}

// Finnhub free plan: /quote returns c (current), dp (percent change since previous close).
async function fetchStocks(env) {
  if (!env.FINNHUB_KEY) return {};
  const out = {};
  for (const sym of STOCKS) {
    const v = await getJson(`https://finnhub.io/api/v1/quote?symbol=${sym}&token=${env.FINNHUB_KEY}`);
    if (typeof v.c === "number" && v.c > 0) out[sym] = { price: v.c, change_pct: v.dp ?? 0 };
  }
  return out;
}

// Frankfurter: European Central Bank reference rates, no key, updated once per working day.
async function fetchFx() {
  const raw = await getJson("https://api.frankfurter.app/latest?from=USD");
  return { USD: 1, ...(raw.rates || {}) };
}
