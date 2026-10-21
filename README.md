# Vault Manager

Isometric pixel art management sim of a small-town precious metal shop. Gold, silver,
platinum and palladium prices follow the real market.

## Layout

| Path | What it is |
| --- | --- |
| `project.godot` | Godot 4.3 project, 480x270 pixel-perfect viewport scaled by whole numbers |
| `autoload/market.gd` | `Market` singleton: metals, crypto, stocks and exchange rates; caches to disk, simulates when offline; formats money in the player's currency |
| `autoload/market_events.gd` | `MarketEvents` singleton: turns real price moves into news headlines and rushes of customers |
| `autoload/shop.gd` | `Shop` singleton: cash, reputation, stock and the day's results; stock is valued at live prices |
| `items/bullion_item.gd` | `BullionItem` resource: value computed from weight x purity x live price, plus the art settings for its coin face |
| `items/counterfeit.gd` | The four kinds of fake (plated steel, brass, copper-nickel clad, tungsten core) and what each does to the readings |
| `data/coins/*.tres` | Real coin specs (weight, purity, diameter, thickness) used by the testing minigame |
| `scenes/shop/` | The isometric shop: room renderer, customers, HUD and the day loop (main scene) |
| `scenes/coin_test/` | The coin testing minigame: scale, calipers, ping, magnet and loupe |
| `art/` | Code-drawn pixel art: bitmap font, iso projection, shop, people and coin painters. No image files |
| `audio/sfx.gd` | Sound effects synthesised at runtime, including each coin's ring |
| `ui/ui_theme.gd` | Pixel UI theme (font, panels, buttons) |
| `tests/smoke_test.tscn` | Headless checks: run `godot --headless --path . res://tests/smoke_test.tscn` |
| `price-service/` | Cloudflare Worker that polls the metals API and serves `GET /prices` |
| `prototype/index.html` | Single-file browser prototype (simulated prices, coin testing minigame) |

## How to play

Customers queue at the counter. Sellers bring coins, buyers want coins from your vault.

- **Test coin** opens the bench. Press 1-5 or click the tools: **Scale** (weight), **Calipers**
  (diameter and thickness), **Ping** (listen to the ring and watch the scope), **Magnet** and
  **Loupe** (move the mouse over the coin). Compare each reading with the spec column, then
  call it **Genuine** or **Fake**. Esc goes back to the counter.
- Fakes you buy are caught by the assay lab a little later, and cost you the money and reputation.
- The **-/+** buttons set what share of melt you pay sellers and the premium you charge buyers.
  Push too far and customers walk.
- Every price comes from the live market feed, so the same coin is worth more or less from one
  day to the next. The LED board on the back wall shows today's spot prices.

## Market events

Big real-world moves make the news, and the news brings customers. A red or green NEWS strip
runs over the shop for about a minute, and most new customers come because of the story:

| Real move | Headline | Who walks in |
| --- | --- | --- |
| Gold down 1% in a day | Gold slides | Panic sellers who accept less than usual |
| Gold up 1% | Gold jumps | Sellers cashing in, holding out for more |
| Silver up or down 2% | Silver squeeze / Silver on sale | Silver buyers, paying extra in a squeeze |
| Platinum up 2% | Platinum pops | Platinum sellers |
| Bitcoin down 4% in 24h | Bitcoin crashes | Crypto converts buying gold at a premium |
| Bitcoin up 4% | Bitcoin soars | Sellers raising cash to chase crypto |
| Dogecoin up 10% | Dogecoin moons | Lucky winners buying gold |
| S&P 500 down or up 1.2% | Stocks tumble / Stocks rally | Safe-haven gold buyers, or sellers moving into shares |
| NVIDIA down 5% | Chip stocks plunge | Tech money buying silver |

Metals compare with the price about a day ago (the price service keeps a day and a half of
metal quotes and sends `metals_change`). Crypto and stocks use the provider's daily change.
A story does not repeat until its move has faded. Triggers and effects live in
`MarketEvents.EVENTS`. In a debug build (playing from the editor), **F9** plays the next event.

## Run

1. Open the folder in Godot 4.3 or later and press Play.
2. Without the price service running, the game starts in "simulated" mode from seed prices.
3. To use live prices, deploy `price-service/`:
   - `npx wrangler kv namespace create PRICES` and paste the id into `wrangler.toml` (only when deploying to a new Cloudflare account)
   - Set the API keys as secrets (never commit them; for local `wrangler dev`, put them in `price-service/.dev.vars`, which is git-ignored):
     `npx wrangler secret put METALCHARTS_KEY`, `COINGECKO_KEY` (optional), `FINNHUB_KEY`
   - `npx wrangler deploy`. `Market.service_url` points at the deployed worker; change it if you deploy your own.

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
