# Melton6 (English edition)

Melton6 is a Windower 4 addon for Final Fantasy XI. With one macro press it runs a Scholar's six-step Immanence skillchain, then Enlightenment and Ebullience, then Kaustra as a magic burst: the "6-chain Kaustra" used against Bumba in Sheol Gaol.

> **Status.** This is the English-client edition of Melton6. It uses the English spell and ability names and the English text in chat. The logic is the same as the Japanese edition ([hikaruoshino/Melton6](https://github.com/hikaruoshino/Melton6)), which I checked in a real fight on the Japanese client. **The English edition has not been tried in game yet.** I have only checked it in a simulated Windower environment (51 checks: the order of the commands it sends, the English names, stopping when something fails). Please try it first on an enemy where a failure costs little, and tell me if something does not work. The Japanese edition sends Japanese spell names, so do not use it on the English client.

## Notice

After a single macro press, Melton6 sends up to 17 job ability and spell commands for you (fewer if Tabula Rasa or Dark Arts is already active, more if an ability misfires and is retried).

- One press runs the sequence once. It does not loop or keep fighting for you.
- If anything goes wrong (the chain does not happen, a cast is interrupted), it stops where it is. It never keeps sending commands after a failure.
- Third-party tools, Windower included, are not permitted by the FFXI Terms of Service. Your account may be penalized, and the author takes no responsibility for any harm from using it. Use it at your own risk.
- Do not leave it running unattended. Watch the screen and press the macro yourself. Please do not modify it for automatic fighting or spam casting.

## What it runs

The Scholar uses Immanence before each of six spells, and the properties stack into a Gravitation chain that Kaustra bursts.

| Step | What it uses | Skillchain |
| :--- | :--- | :--- |
| Prep | Tabula Rasa and Dark Arts (skipped if already active) | |
| 1 | Immanence, then Aero | (opener: Detonation) |
| 2 | Immanence, then Stone | Scission |
| 3 | Immanence, then Aero | Detonation |
| 4 | Immanence, then Geohelix | Scission |
| 5 | Immanence, then Anemohelix | Detonation |
| 6 | Immanence, then Noctohelix | Gravitation |
| MB | Enlightenment, then Ebullience, then Kaustra | Darkness on Gravitation: magic burst |

- Kaustra can only be cast while Tabula Rasa is active, so if it has worn off the addon uses it first (`//m6 tabula` toggles that).
- Tabula Rasa is active for all six Immanence casts and for Ebullience, so no Grimoire stratagems are spent on them.
- Ending a chain with a helix gives the magic burst window 2 extra seconds (8 + 2 = 10 seconds).
- Melton6 does not change your gear. It sends the abilities and spells as ordinary commands, so your usual GearSwap does the swapping (see "GearSwap" below).

## How it advances, and when it stops

- **Abilities.** It checks the ability packet, then waits 1 second before the next step. (Ebullience misfires unless it is used at least 1 second after Enlightenment.) If an ability did not fire, it is tried once more.
- **Enlightenment and Ebullience.** Lag can make either one misfire, so if at least one of them fires, the addon carries on to Kaustra. Only if both fail does it stop without casting Kaustra. To make the burst window, these two are never retried, and the wait for each is only 1.5 seconds. If a packet arrives late because of lag, it still counts as fired.
- **Spells.** It checks that the cast starts and that the spell lands. From step 2 on, it also checks that the intended skillchain happened, and it waits 3 seconds after the spell lands before the next step.

It stops at once, and says why in chat, when:

- a cast is interrupted, a cast does not start, or a landing is not confirmed
- the intended skillchain did not happen
- an ability failed twice (for Enlightenment and Ebullience, when both failed)
- your target changed or died, you changed zones, or you were knocked out
- you run `//m6 stop`, log out, or hit an internal error

Tabula Rasa has a one-hour recharge, so stopping halfway is expensive. Before it starts anything, the addon checks that you are a Scholar, that you have an enemy targeted and are in range, that the helix spells, Kaustra, Enlightenment and Tabula Rasa are ready, and that you have enough MP. If something is missing it does nothing and lists everything at once. `//m6 check` runs only this check.

When it finishes, it reports whether the burst worked, which of Enlightenment and Ebullience took effect, and the seconds from the Gravitation landing to the Kaustra landing. In one real fight, the Japanese build reported a burst 7.17 seconds after the Gravitation landing, leaving about 2.8 seconds of the 10-second window. The waits are chosen so that a late Enlightenment combined with a failed Ebullience should still fit in the 10 seconds, assuming fast gear.

## GearSwap

Without GearSwap the addon still runs, but you will not swap into fast cast gear before casting, the gear for the Immanence spells, or your Kaustra burst gear. Casts then take longer and may miss the 10-second window, and Kaustra does much less damage. I recommend GearSwap.

I use the Scholar files (`SCH.lua`, `SCH_gear.lua`) from [greeds.net's GearSwap code list](https://greeds.net/gearswap-code-list/) as my base, and I have checked Melton6 with them. Rewrite `SCH_gear.lua` for your own gear. The files and layout are described on greeds.net, so follow that page for the latest. Melton6 is a personal project and has no connection to greeds.net; ask them about their code.

My own modified Scholar GearSwap (`SCH.lua`, `SCH_gear.lua`, `weather_obi.lua`), based on the greeds.net version, has an English edition at [hikaruoshino/SCH-GearSwap-EN](https://github.com/hikaruoshino/SCH-GearSwap-EN) (the Japanese-client edition is [hikaruoshino/SCH-GearSwap](https://github.com/hikaruoshino/SCH-GearSwap)). Its gear is matched to my inventory, so rewrite it before you use it.

Gear tips:

- **Fast cast.** In places where your support job drops to level 0, such as Sheol Gaol, you lose the Red Mage fast cast trait. Aim for the 80% fast cast cap from gear alone.
- **Keep the weapon type the same.** If the weapon type changes between your fast cast, Immanence and burst sets, your appearance flickers at every swap. Use the same type everywhere (for example, a club and a shield).
- **Immanence spells.** They only set up the chain, so keep the damage low, and use Subtle Blow gear so you do not feed the enemy TP. For reference, see [this Scholar magic burst gear article on spoiler.jp](https://www.spoiler.jp/blog/2026/03/11schmb/) (in Japanese).

## Installation

1. Download the repository (Code > Download ZIP) and unzip it. GitHub names the folder `Melton6-EN-main`; rename it to `Melton6`. The addon will not load under another name.
2. Put the `Melton6` folder (with `Melton6.lua` in it) in `Windower4/addons/`. If you use the Japanese edition too, use only one of them: they share the folder name and the `data/` settings.
3. In game, run `//lua load Melton6`.
4. Put this single line in a macro:

```
/console m6 go
```

5. Run `//m6 check` to confirm everything is ready, target an enemy, and press the macro.

The only requirement is Windower 4; the libraries it uses (`config` and `resources`) ship with it. GearSwap is recommended, as explained above.

## Commands (`//m6` or `//melton6`)

| Command | What it does |
| :--- | :--- |
| `//m6 go` | Start the 6-step skillchain into Kaustra |
| `//m6 stop` | Stop partway |
| `//m6 check` | Check whether it can start, and run nothing |
| `//m6 status` | Show the settings |
| `//m6 set post <sec>` | Wait from a spell landing to the next ability (default 3.0, range 0-10). Adjust it if the chain does not form |
| `//m6 set gap <sec>` | Wait after an ability (default 1.0, range 0.5-5) |
| `//m6 set boosttimeout <sec>` | How long to wait for Enlightenment and Ebullience to fire (default 1.5, range 0.5-5) |
| `//m6 set jatimeout <sec>` | How long to wait for any other ability to fire (default 2.5, range 0.5-10) |
| `//m6 set retries <n>` | How many times to use an ability again if it did not fire (default 1, range 0-2; Enlightenment and Ebullience are never retried) |
| `//m6 set casttimeout <sec>` | How long to wait for a cast to start (default 2.5, range 1-10) |
| `//m6 set landtimeout <sec>` | How long to wait for a spell to land after the cast starts (default 12.0, range 3-30) |
| `//m6 tabula` | Whether to use Tabula Rasa automatically when it has worn off (ON / OFF) |

Settings are saved in `data/settings.xml`. Values outside the range are pulled back into it, with a message; this also applies to values written into `data/settings.xml` by hand (since 1.0.1).

## Notes

- The default waits come from a macro written by someone else (see below) and have been tried in real fights. If your connection makes the chain hard to form, adjust them with `//m6 set post`.
- Against an enemy that always takes 0 damage (such as the scarecrows in Jeuno), the chain forms but Kaustra does not become a magic burst. Test against a real enemy.
- The sequence is based on a macro from the Japanese blog "モーター、あなた疲れてるのよ" (the post "バンバ用6連2アビメルトンMBを安定化"): https://mortar.hateblo.jp/entry/2023/06/15/195116

## License

MIT License.

## Changelog

- **v1.0.1 (2026-10-28).** Settings now have ranges (retries 0-2, waits and timeouts as listed above). Out-of-range values such as `//m6 set retries 50`, zero or negative numbers could make it resend an ability many times or send inputs back to back. The pre-start check now covers the Aero and Stone recasts too, so it won't stop at the second step and waste Tabula Rasa. The result message (burst or no burst) now names the target. Tested in game on the Japanese client.
- **English edition (2026-10-23).** The same logic as v1.0.0 with English spell and ability names (read from Windower's resources), English chat text and English skillchain names. Not tried in game yet.
- **v1.0.0 (2026-10-09, Japanese edition).** First release: the six-step Immanence chain, Enlightenment, Ebullience and the Kaustra burst on one macro press. It advances by checking execution, landing, skillchain and burst packets, and stops on failure. If either Enlightenment or Ebullience fires, it carries on to Kaustra.

## Feedback

A one-line "it works" is welcome too. With a GitHub account you can post from [Issues](../../issues/new/choose).
