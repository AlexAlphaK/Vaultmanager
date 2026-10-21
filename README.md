# Vault Manager

Isometric pixel art management sim of a small-town precious metal shop. Gold, silver,
platinum and palladium prices follow the real market.

## Layout

| Path | What it is |
| --- | --- |
| `project.godot` | Godot 4.3 project, 480x270 pixel-perfect viewport scaled by whole numbers |
| `autoload/market.gd` | `Market` singleton: metals, crypto, stocks and exchange rates; caches to disk, simulates when offline; formats money in the player's currency |
| `autoload/shop.gd` | `Shop` singleton: cash, reputation, stock and the day's results; stock is valued at live prices |
| `autoload/day.gd` | `Day` singleton: day phases (morning, open, closing, after hours), the week, bills and the day's ledger |
| `autoload/progress.gd` | `Progress` singleton: the four shop tiers, upgrades and their effects |
| `autoload/save_game.gd` | `SaveGame` singleton: saves to `user://save.json` every morning, loads on launch |
| `items/bullion_item.gd` | `BullionItem` resource: value computed from weight x purity x live price, plus the art settings for its coin face |
| `items/counterfeit.gd` | The four kinds of fake (plated steel, brass, copper-nickel clad, tungsten core) and what each does to the readings |
| `data/coins/*.tres` | Real coin specs (weight, purity, diameter, thickness) used by the testing minigame |
| `scenes/shop/` | The isometric shop: room renderer, customers, HUD, morning/upgrades/summary panels and the day loop (main scene) |
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

### A day in the shop

1. **Morning.** The shop is shut. Check the market hint and the bills, set your prices with
   **-/+**, and buy upgrades. Press **Open the shop**.
2. **Open.** Customers come and go for about three minutes (09:00 to 17:00 on the wall clock).
3. **Closing.** No new customers; serve the ones still in the queue.
4. **After hours.** The summary shows the day's deals and bills. **Lock up and go home** starts
   the next morning, and the game saves.

Upkeep is paid every night. Rent and insurance (0.2% of your vault's value) are paid every
Sunday night, so keep some cash back. If cash goes negative the bank charges 0.5% a night,
but you never go bust: you just can't buy until you sell your way out.

The game saves every morning. Quitting mid-day replays that day from the morning.
**New game** (click twice) wipes the save.

### Growing the shop

The goal is to become the biggest precious metal store in town. Move up through four tiers
from the **Upgrades** page once you have the net worth, stars and cash:

| Tier | Needs net worth | Stars | Moving cost | Weekly rent | Customers |
| --- | --- | --- | --- | --- | --- |
| Corner counter | | | | $1,200 | normal |
| Main Street shop | $60,000 | 3.0 | $15,000 | $3,000 | 25% more often, 1.5x bigger deals |
| Bullion house | $160,000 | 3.8 | $45,000 | $8,000 | 50% more often, 2.2x bigger deals |
| Town landmark | $400,000 | 4.5 | $120,000 | $18,000 | 80% more often, 3.2x bigger deals |

Each tier also unlocks new upgrades (waiting bench, neon sign, display lights, alarm, fraud
insurance, second safe, radio ads, collector's lounge, time-lock vault, billboard).

### Hooks for other systems

- `Day` signals: `day_started`, `shop_opened`, `shop_closed`, `day_ended(day, report)` and
  `phase_changed`. Append strings to `report.lines` in `day_ended` to show them in the summary.
- `Day.add_income(label, usd)` / `Day.add_expense(label, usd)` move cash and list the line in
  tonight's summary (robbery losses, event bonuses, staff wages).
- `Progress.tier`, `Progress.effect("robbery_risk")`, `Progress.safe_capacity()` and
  `Progress.register_upgrade(id, data)` for new tools, safes and gating content by tier.
- `SaveGame.register(key, save_fn, load_fn)` adds a module's state to the save file.

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
