// Vault Manager price service (Cloudflare Worker).
// A cron trigger polls the metals provider every 5 minutes and stores the quote in KV.
// Every game client reads GET /prices, so one API key and one rate limit cover all players.
//
// Response: { "prices": { "XAU": 4473.37, "XAG": 73.31, "XPT": 1879.64, "XPD": 1520.0 }, "updated": "<ISO time>" }

const METALS = ["XAU", "XAG", "XPT", "XPD"];
const PROVIDER_URL = "https://api.metalcharts.org/v1/prices";

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname !== "/prices") return new Response("Not found", { status: 404 });
    let body = await env.PRICES.get("latest");
    if (!body) body = JSON.stringify(await refresh(env));
    return new Response(body, {
      headers: { "content-type": "application/json", "access-control-allow-origin": "*", "cache-control": "max-age=60" },
    });
  },
  async scheduled(_event, env) {
    await refresh(env);
  },
};

async function refresh(env) {
  const res = await fetch(PROVIDER_URL, { headers: { Authorization: `Bearer ${env.METALCHARTS_KEY}` } });
  if (!res.ok) throw new Error(`provider returned ${res.status}`);
  const raw = await res.json();
  const quote = { prices: normalize(raw), updated: new Date().toISOString() };
  await env.PRICES.put("latest", JSON.stringify(quote));
  return quote;
}

// The provider nests each metal under data.<SYMBOL>. The exact field holding the
// USD price is not confirmed yet, so accept the common spellings until one real call is checked.
function normalize(raw) {
  const out = {};
  for (const m of METALS) {
    const v = raw?.data?.[m];
    const price = typeof v === "number" ? v : v?.price ?? v?.usd ?? v?.value ?? v?.spot;
    if (typeof price === "number") out[m] = price;
  }
  return out;
}
