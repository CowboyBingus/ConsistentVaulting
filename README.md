> Current local compatibility candidate for Steam build 25480438 / EXE 1.8.46015.0. Offline checks passed; live gameplay verification is pending.

Vaulting repair v8.7: Gives higher-ledge discovery its own fresh native approach geometry when the ordinary-height approach rejects and shared query slots have been reused. Height, slope, motion, exit and ownership checks remain; no climb is forced. Installed obstacle confirmation remains pending.

![Consistent Vaulting](assets/banner.png)

# Consistent Vaulting

Makes manual vaulting more forgiving than vanilla by checking obstacles again when an otherwise usable climb is rejected.

- **Fewer position-sensitive refusals.** Fresh obstacle checks adapt to your approach, and eligible manual retries can recover when an obstacle's vault-blocking tag prevents the normal selection.
- **Higher reachable ledges.** Grounded top detection can temporarily extend climb height from vanilla's 1.95 to 2.5 game units when it finds a suitable landing.
- **Controlled steep-surface climbing.** Validated slopes up to 65 degrees can receive temporary support. Walking speed applies after an assisted steep climb begins and while that bounded support is needed.
- **Normal movement between attempts.** Pressing climb in open space does not slow the Helldiver; allowances require a usable nearby candidate and end when the attempt or support conditions expire.

Changes apply only to your Helldiver. Collision, clearance, reach and moving-obstacle checks still govern whether a climb can happen.

Release **v8.2** includes input/performance fixes. Offline checks cover this revision; in-game frame-time validation is pending. Routine diagnostics are off by default; developers can set `CowboyBingusDiagnostics = true` before initialization to enable them.

Current version: **v8.7**, for game build **25480438**. See [changes](CHANGELOG.md) and [validation coverage](docs/MIGRATION_VALIDATION.md).
