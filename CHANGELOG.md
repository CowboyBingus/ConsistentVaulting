# v8.8

- Slope assist reads only the input state while no assist is active and the vault input is released; the mover, controller, settings and flags are still read and validated in full on every press and during every assist.
- Verifies the native function tables once per session instead of on every check, decodes fields without copying the rest of each buffer, computes each hash-lookup product once and reuses one read buffer.
- Measured in real play: about 0.44 ms to 0.25 ms of main-thread time per frame in missions, and 4.0 to 3.4 MB/s of Lua garbage. Vaulting, slope and ledge assists were confirmed live.

# v8.7

- Support Steam build 25480438 with refreshed native guards.
- Preserve higher-ledge detection and bounded slope assistance.
- Offline builds and package checks pass; live gameplay validation remains pending.

# v8.6

- Update compatibility for game build 25327279.
- Fix higher-ledge detection and fresh climb attempts.
- Preserve obstacle clearance, slope and movement checks.

# v8.2

- Disable periodic diagnostic file writes and console output by default.
- Keep startup, failure and shutdown reports available.
- Preserve vaulting checks and movement behavior.
- Offline regression checks cover this update; live frame-time verification remains pending.

# v8.1

- Enables vaulting corrections and slope assistance on defense and other supported mission types.
- Moves logs to `%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs`.
- Requires Bingus Shared Loader v14 for the shared log folder.
