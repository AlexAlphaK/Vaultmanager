# Vault Manager

Isometric pixel art management sim of a small-town precious metal shop. Gold, silver,
platinum and palladium prices follow the real market.

## Layout

| Path | What it is |
| --- | --- |
| `project.godot` | Godot 4.3 project, 480x270 pixel-perfect viewport scaled by whole numbers |
| `autoload/market.gd` | `Market` singleton: polls the price service, caches to disk, simulates when offline |
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
   - `npx wrangler secret put METALCHARTS_KEY` (never commit the key; for local `wrangler dev`, put it in `price-service/.dev.vars`, which is git-ignored)
   - `npx wrangler deploy`, then set `Market.service_url` to the worker's `/prices` URL.

Design doc: https://claude.ai/artifact/VqviQgHanNwibT95FhXgLV

## Feed states

- `live`: a fresh quote arrived from the price service.
- `cached`: the service is unreachable; the last real quote is used.
- `simulated`: no real quote for over 24 hours (or never); prices follow a random walk with realistic volatility.
