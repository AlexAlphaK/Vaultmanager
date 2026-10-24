# Vault Manager: Steam store page kit

Everything here is made from the real game by `tools/store/make_store_assets.sh`, so it can be
rebuilt after the game changes. Paste the text below into Steamworks (Store Page Admin), and upload
the images and the trailer from this folder.

## What goes where in Steamworks

| Steamworks field | File | Size |
| --- | --- | --- |
| Screenshots (at least 5) | `screenshots/*.png` | 1920x1080 |
| Trailer | `trailer/vault_manager_trailer.mp4` | 1080p, 30 fps, 84 s, with sound |
| Header capsule | `art/header_capsule.png` | 920x430 |
| Small capsule | `art/small_capsule.png` | 462x174 |
| Main capsule | `art/main_capsule.png` | 1232x706 |
| Vertical capsule | `art/vertical_capsule.png` | 748x896 |
| Page background | `art/page_background.png` | 1438x810 |
| Library capsule | `art/library_capsule.png` | 600x900 |
| Library hero | `art/library_hero.png` | 3840x1240 |
| Library logo | `art/library_logo.png` | 1280x720, transparent |
| Client icon | `art/icon.ico` | 16, 32, 48 and 256 px |
| Community icon | `art/community_icon.jpg` | 184x184 |

The same vault door icon is now the game's window icon (`icon.png`).

Suggested screenshot order: shop floor, coin bench, bar bench, jewellery bench, hold-up, vault,
trading desk, town map, title.

## Game name

Vault Manager

## Short description (shown next to the capsule, 300 characters max)

Run a small-town gold and silver shop where prices follow the real market. Test coins, bars and
jewellery for fakes on hands-on pixel art benches, haggle with every customer, lock up the vault
before the burglars come, and grow your corner counter into the biggest bullion house in town.

## About this game

**Buy low. Test everything. Lock it up.**

You've just bought Mags Holloway's corner counter: a till, a magnifying loupe and forty years of
regulars. Across the street, Victor Sterling of Sterling Bullion Co. gives you a month.

**Prices from the real world**
Gold, silver, platinum and palladium follow the real market. When gold jumps in real life, sellers
line up to cash in. When it dips, buyers come looking for a bargain. Crypto and stocks move too,
and the morning news turns real price moves into rushes at your door.

**Hands-on testing benches**
Every deal is a small puzzle. Weigh coins, measure them with calipers, listen to their ring and try
the magnet. Rub jewellery on the touchstone and drop acids on the streak, then check the stone with
a thermal tester. Sweep kilo bars with an ultrasound probe for hidden tungsten cores and read their
surface with an XRF gun. The fakes get better as you grow.

**Every customer haggles**
Widows clearing out a collection, crypto bros, collectors hunting one rare date, regulars with
stories that play out over weeks, and shady sellers who are hoping you won't look too closely.
Set what you pay and what you charge, and watch who walks out.

**Grow from a corner counter to the town landmark**
Four shops, each bigger than the last. Buy upgrades, hire a clerk and a guard, build a testing lab,
a refining workshop and a trading desk, and fill special orders for collectors. Push past Lucky's
Pawn and Sterling Bullion on the town map.

**Keep it safe**
Robbers walk in with the customers. Burglar crews case the shop at night. Before the lights go out,
pack your coins, bars and cash into the safes in a race against the clock.

**A year in town**
Tax season, gold fever week, the coin show and the holiday gift rush each bring their own customers.
A short story campaign follows Mags and Victor from your first week to the ribbon cutting.

**Features**
- Precious metal prices tied to the real market, in your own currency
- Three testing benches with 16 tools: coins, jewellery and bullion bars
- Isometric pixel art shop that grows through four tiers
- Morning trading desk: trade metals, stocks and crypto and hedge your vault
- Hold-ups, burglar crews, security cameras and the nightly vault lock-up
- Rival shops, seasons and town events, special orders and rare coins
- Story campaign, 28 achievements and a lifetime ledger
- Full controller support, built for Steam Deck
- Original synthesized music and sound

## Tags to pick

Simulation, Management, Pixel Graphics, Isometric, Economy, Trading, Minigames, Business,
Singleplayer, Casual, Indie, Strategy, Controller

## System requirements (Windows)

| | Minimum |
| --- | --- |
| OS | Windows 10 64-bit |
| Processor | Dual core 2 GHz |
| Memory | 2 GB RAM |
| Graphics | OpenGL 3.3 or Vulkan 1.0 capable |
| Storage | 200 MB |
| Network | Internet connection for live prices (plays offline on simulated prices) |

Check these against the real Windows build before publishing; the build has not been tried on a
real Windows PC yet.

## Before you publish

- **Steamworks account.** Steam Direct costs $100 per game. You sign up at partner.steamgames.com
  with your own details (tax and bank info), then upload these files. I can't do that part for you.
- **Coin names.** The coins now have made-up names (Liberty Hawk, Frostleaf, Veldrand, Albion and
  so on) instead of real mint trademarks like Krugerrand or Maple Leaf. Bar brands were already
  fictional. Keep any new coins fictional too.
- **Price service.** The game's live prices come from your Cloudflare Worker and the API keys
  behind it. Rotate the keys that were pasted in chat, and check the free tiers cover the players
  you expect.
- **"Wishlist on Steam"** is the trailer's end card. Change the line in `tools/store/capture.gd`
  (`_end_card`) if you'd rather say something else, and rebuild with
  `tools/store/make_store_assets.sh trailer`.
