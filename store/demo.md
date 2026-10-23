# Vault Manager demo: Steamworks checklist

The demo build is ready to upload: every merge into `main` publishes
`VaultManagerDemo-windows.zip` on the **Latest Windows demo** release
(https://github.com/AlexAlphaK/Vaultmanager/releases/tag/demo-latest). It plays the first 10 days,
lets the shop reach Main Street, and ends on a thank-you screen with a **Wishlist on Steam** button.

Everything below needs your own Steamworks account, so it is yours to do.

## 1. Before the demo

1. Pay the Steam Direct fee and create the full game's app (store page kit: `store/store_page.md`).
2. Put the full game's app id in `STEAM_APP_ID` in `autoload/demo.gd` and merge it, so the wishlist
   button opens the store page instead of a search. A new demo build follows automatically.
3. The store page must be live ("Coming soon") before a demo can be released.

## 2. Create the demo app

1. In Steamworks, open the full game's app, then **All Associated Packages, DLC, Demos and Tools**.
2. Under **Demos**, click **Create new demo**. Steam gives the demo its own app id and depot id.
3. Fill in the demo's store details. The capsules and screenshots in `store/` work for it too.

## 3. Upload the build

Either way, start from `VaultManagerDemo-windows.zip`, unzipped: one file, `VaultManagerDemo.exe`.

**With the Steamworks web uploader (simplest).** In the demo app, open **SteamPipe > Builds**,
upload the zip under "Upload a zip file", and set the build live on the `default` branch.

**With SteamCMD.** `store/steampipe/` has the two build scripts. Replace `DEMO_APP_ID` and
`DEMO_DEPOT_ID` with the demo's ids, put `VaultManagerDemo.exe` in `store/steampipe/content/`, then:

```
steamcmd +login <your Steam login> +run_app_build "<full path to>\store\steampipe\app_build_demo.vdf" +quit
```

## 4. Launch options and release

1. **Installation > General**: add a launch option, executable `VaultManagerDemo.exe`, OS Windows.
2. **Steam Deck**: the game supports controllers and scales to the Deck's screen (see the
   README's "Controller and Steam Deck" section), so ask for a Deck review once the demo is up.
3. Publish the demo's store page and press **Release** on the demo. For Next Fest, register the
   game in the Steamworks **Upcoming events** page before the deadline; the demo must be live
   for the festival week.

## What the demo includes

| | Demo | Full game |
| --- | --- | --- |
| Days | 10 | Endless |
| Shop tiers | Corner counter, Main Street | Up to the town landmark |
| Benches, customers, robberies, staff, seasons | Yes | Yes |
| Story | As far as 10 days get you | All five chapters |
| Saves | Its own three slots | Its own three slots |

To change the limits, edit `DAYS` and `MAX_TIER` in `autoload/demo.gd`.
