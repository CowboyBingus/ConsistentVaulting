> Release **v8.9.1** for Steam build 25480438 / EXE 1.8.46015.0. Offline checks passed; vaulting, slope and ledge assists were confirmed in live play.

![Consistent Vaulting](assets/banner.png)

# Consistent Vaulting

Makes manual vaulting more forgiving than vanilla by checking obstacles again when an otherwise usable climb is rejected.

- **Fewer position-sensitive refusals.** Fresh obstacle checks adapt to your approach, and eligible manual retries can recover when an obstacle's vault-blocking tag prevents the normal selection.
- **Higher reachable ledges.** Grounded top detection can temporarily extend climb height from vanilla's 1.95 to 2.5 game units when it finds a suitable landing.
- **Controlled steep-surface climbing.** Validated slopes up to 65 degrees can receive temporary support. Walking speed applies after an assisted steep climb begins and while that bounded support is needed.
- **Normal movement between attempts.** Pressing climb in open space does not slow the Helldiver; allowances require a usable nearby candidate and end when the attempt or support conditions expire.

Changes apply only to your Helldiver. Collision, clearance, reach and moving-obstacle checks still govern whether a climb can happen.

The mod re-verifies your Helldiver instead of locating it on every check and pauses instead of stopping after errors elsewhere in the update chain. Release **v8.9.1** waits for the climb input: in a mission, while it is released, a frame reads only that input and the full check runs every 10th frame; outside a mission the mod checks every 60th frame. Measured in game: 0.008-0.009 ms per frame in missions and 0.003 on the ship. Routine diagnostics are off by default; developers can set `CowboyBingusDiagnostics = true` before initialization to enable them.

**Install:** close the game, import `Consistent-Vaulting-v8.9.1.zip` and Bingus Shared Loader v18 or newer into Arsenal or HD2MM, enable both and Purge / Deploy. With Arsenal's default priority, put the loader last. [Bingus Shared Loader](https://github.com/CowboyBingus/BingusSharedLoader/releases/latest) is a separate required download.

Current version: **v8.9.1**, for game build **25480438**. See [changes](CHANGELOG.md) and [validation coverage](docs/MIGRATION_VALIDATION.md).

**AI disclosure:** Developed with assistance from GPT-6 Astra and Claude Opus 5.5.

## License

Zero-Clause BSD (0BSD): use, copy, modify and distribute for any purpose, with no conditions. See `LICENSE`.
