# Vault Manager

Isometric pixel art management sim of a small-town precious metal shop. Gold, silver,
platinum and palladium prices follow the real market.

## Layout

| Path | What it is |
| --- | --- |
| `project.godot` | Godot 4.3 project, 480x270 pixel-perfect viewport scaled by whole numbers |
| `autoload/market.gd` | `Market` singleton: metals, crypto, stocks and exchange rates; caches to disk, simulates when offline; formats money in the player's currency |
| `items/bullion_item.gd` | `BullionItem` resource: value computed from weight x purity x live price |
| `data/coins/*.tres` | Real coin specs (weight, purity, diameter) used by the testing minigame |
| `scenes/main.tscn` | Placeholder scene showing the ticker and vault value |
| `price-service/` | Cloudflare Worker that polls the metals API and serves `GET /prices` |
| `prototype/index.html` | Single-file browser prototype (simulated prices, coin testing minigame) |

## Run

1. Open the folder in Godot 4.3 or later and press Play.
2. Without the price service running, the game starts in "simulated" mode from seed prices.
3. To use live prices, deploy `price-service/`:
   - `npx wrangler kv namespace create PRICES` and paste the id into `wrangler.toml`
   - Set the API keys as secrets (never commit them; for local `wrangler dev`, put them in `price-service/.dev.vars`, which is git-ignored):
     `npx wrangler secret put METALCHARTS_KEY`, `COINGECKO_KEY` (optional), `FINNHUB_KEY`
   - `npx wrangler deploy`, then set `Market.service_url` to the worker's `/prices` URL.

Design doc: https://claude.ai/artifact/VqviQgHanNwibT95FhXgLV

## Data sources

| Data | Provider | Free tier (check before launch) | Refresh |
| --- | --- | --- | --- |
| Gold, silver, platinum, palladium | MetalCharts | ~200 calls/month, attribution link required | every 4 hours |
| Crypto (BTC, ETH, SOL, DOGE) | CoinGecko demo plan | free key, ~30 calls/min, attribution required | every 5 minutes |
| Stocks (SPY, AAPL, NVDA, TSLA) | Finnhub free plan | free key, ~60 calls/min | every 5 minutes |
| Exchange rates | Frankfurter (ECB reference rates) | no key | every 4 hours (ECB updates daily) |

## Currency

Everything runs in USD internally. `Market.format_money()` converts for display. The default
currency comes from the device locale (e.g. `de_DE` shows euros); players can change it, and
the choice is saved in `user://settings.cfg`.

## Feed states

- `live`: a fresh quote arrived from the price service.
- `cached`: the service is unreachable; the last real quote is used.
- `simulated`: no real quote for over 24 hours (or never); prices follow a random walk with realistic volatility.
