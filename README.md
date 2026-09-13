# Consistent Vaulting

Retries usable surfaces when an earlier candidate blocks a manual vault. If no normally permitted candidate works, it can tolerate the selected obstacle's manual-climb metadata veto after the game's existing exit checks pass.

**data-v3 prerelease. Requires Bingus Shared Loader loader-v4 or newer / API 1 or newer.** Built for Steam build 24826606 / EXE 1.8.45317.0. Offline validation passes; the revised native retry still needs gameplay validation.

data-v3 accepts newer shared-loader APIs. Gameplay behavior is unchanged from data-v2.

Import `ConsistentVaulting.zip` and the updated `BingusSharedLoader.zip` into Arsenal or HD2MM. Enable both, then Purge and Deploy with the game closed. With Arsenal's default priority, place the loader last. See [installation](INSTALL.txt).

The mod resolves the installing player's avatar by identity. It changes only that avatar's temporary query results and phase, then calls the game's original local vault routine. It leaves teammates' records, shared obstacle flags, collision filters, height/reach settings, and input bindings unchanged. No custom DLL or executable patch is installed. Teammates do not need the package; host/client behavior still needs in-game validation.

Use your normal manual climb input. The native engine keeps control of the actual vault, including its final geometry and animation decisions. Automatic input alone causes no query edits. Prepared candidates do not guarantee successful traversal of every obstacle.

Live testing found that data-v1 loaded but never caught the brief native query stage. Data-v2 also handles the completed stage: it verifies the current approach in private storage, refreshes existing collision queries, and retries through the original vault routine. Retained hits alone cannot authorize a retry. An idle scheduler, matching local identity, manual input and native state checks are required.

The log is `%LOCALAPPDATA%/ConsistentVaulting.log`, with a heartbeat every two seconds while the callback runs. `updates` and `polls` show callback activity; `stage_0` through `stage_3` show observed phases. `fresh_queries` counts synchronous casts, `retry_calls` counts calls to the original vault routine, and `native_starts` counts a newly observed native climbing state after a retry. `prepared` and `native_starts` do not prove a completed traversal or improvement across all obstacles.

[Technical details and validation](docs/TECHNICAL.md). Build with `python -B scripts/build.py`; use `HD2_LUAJIT` for the game's Windows x64 LuaJIT bytecode compiler and `HD2_GAME_ROOT` for a nonstandard installation. In this workspace the builder reuses the root project's LuaJIT compiler and writes `ConsistentVaulting.zip` to the base `releases/` directory. A standalone checkout uses its own base directory. Building does not install or launch the game.

Developed with assistance from GPT-6 Astra.
