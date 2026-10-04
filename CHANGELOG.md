# v8.9

- One check per frame instead of two while nothing is in progress; the second check, after the game's update, runs only while a vault edit is held, an assist or its press window is active, or a vault query meets the held input.
- While the input is released, a check reads 7 values instead of 37-39: it re-verifies the local avatar it found before instead of locating it again.
- With the input held but no vault query, a check reads 19 values instead of 37-39; neither case takes a timestamp.
- Outside a mission a check reads 2 values instead of 4.
- While no vault can happen, a check creates no Lua garbage (about 3.1 KB per frame in a mission and 0.8 KB outside one before).
- While a vault query meets the held input, the vault part reuses the avatar the slope part just located (about 18 reads fewer per check).
- A held vault edit stays in place while each check would make the same edit, instead of being restored and written again: up to six memory-protection queries per frame fewer.
- A kept vault edit is no longer read a second time right after the check: 92 reads instead of 174 per check in the offline fixture; every write still checks first.
- Memory protection is checked once per region a check writes: an assist arms with 2 protection queries instead of 6 and releases with 3 instead of 8.
- Arming and releasing a slope or ledge assist verify its game data once around their writes: about 150 and 110 fewer memory reads per assist.
- With the input held or an assist active, the assist settings come from a read already made (3 reads fewer per check), and an invalid float in memory decodes as a plain NaN.
- An error raised by the game's update or another mod's now passes through unchanged, so its stack trace starts where it was raised.
- After such an error the mod restores its changes and pauses, then resumes once the game's update has run without error for 60 frames.
- An unexpected error inside the mod no longer stops it at once: it restores its changes and starts over.
- Eight errors of either kind without an error-free minute between them still stop the mod for the session.
- The shutdown status keeps the first failure (`stopped after: <reason>`) instead of overwriting it with `stopped`.
- A restore that raises no longer reaches the game's update or shutdown; it is reported as `local_restore_failed`.
- Calls Windows through Bingus Shared Runtime v1 under private names, so another mod's declarations of the same functions can no longer change this mod's calls.
- Each game module's hash is read once per session for every mod that uses the runtime.
- The mod is now licensed under the Zero-Clause BSD license (0BSD).
- Measured in live play: 0.026 ms per frame in client missions and 0.011 on the ship.

# v8.8.1

- Documentation-only release: the mod is identical to v8.8 (same compiled resource).
- Rewrites the install notes packaged with the mod and the README status: one current status line instead of the compatibility-candidate notes left from the game-build update, and removes an old note that frame-time validation was pending. Vaulting, slope and ledge assists were confirmed in live play.
- Lists one loader requirement, Bingus Shared Loader v18.

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
