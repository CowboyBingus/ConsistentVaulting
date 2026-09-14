# Implementation and validation

## Supported runtime

The module is locked to Steam build 24826606 / EXE 1.8.45317.0 and the module hashes in `scripts/archive.py`. It loads as `mods/cowboybingus/consistent_vaulting` through Bingus Shared Loader loader-v4 or newer / API 1 or newer. The resource name and mod-manager GUID are compatibility identifiers.

The package supplies stripped LuaJIT bytecode. It invokes existing engine functions through FFI and uses existing writable private data. It installs no custom DLL, executable-memory allocation, instruction patch or protection change.

## Local ownership and lifetime

The player manager supplies the local unit reference. Entity and avatar maps resolve the controller, effective settings and mover. Mission state, entity resource, ownership, registry equality, controller identity and manual input must agree. Index zero is not assumed to identify the local player.

Completed stage-2 queries and retained stage-3 queries are supported. Every descriptor must point into the resolved local controller, use the expected filter/type, ignore the correct avatar, and have one-hit capacity. Stage 3 requires an idle scheduler and all eight workers complete. Reused descriptors or unavailable snapshots are skipped.

Writes are guarded by the original entity/query epoch and byte values. Stage-2 edits are restored before reevaluation; stage-3 edits are restored immediately after the original native retry. Changed identity or reused storage prevents restoration by stale address. Failed or partial writes attempt rollback. Shutdown and original-update exceptions use the same cleanup.

## Manual candidate selection

Fresh candidates must pass the current surface-angle threshold, actor-motion limit, ground/air height allowance, reach and native exit validation. An eligible candidate without the manual metadata veto is preferred. Otherwise, one validated fallback uses the native selector's existing no-actor representation only in that local query result. Shared obstacle flags are unchanged.

The existing climbing state, pending readiness at controller +532 and the original A88020/A88160 eligibility masks prevent a retry. Controller +533 reports an automatic step; it can remain set when a later lower-candidate search finds nothing. The native manual eligibility routine does not use that report as a veto. The mod preserves it without directly setting or clearing it.

During active manual input, stage-3 retries run at most ten times per second. Only previously nonempty slots can supply a refreshed result for consumption because native result counts remain unchanged. The original automatic-step prepass also sees the selected result; the engine owns the choice between stepping and vaulting.

## Fresh approach geometry

A private aligned controller copy enters stage zero and runs the original approach detector with zero delta time. Controller consumption requires a successful stage-1 approach.

When any of the eleven geometry floats differs by more than 0.02 game units from the retained batch, the mod reconstructs private descriptors using the recovered native producer formula. It validates identity, finite dimensions and the native horizontal forward/up basis. Ten source positions interpolate between the approach endpoints; each box uses half the native width, one twentieth of the endpoint separation, and 0.05 vertical half-extent. Sweep endpoints follow the native vertical span and offsets with float32 rounding.

Only private matrix/translation, dimensions and sweep targets change. The scheduler, real controller geometry, output ownership, filters, ignored unit and capacity are preserved. Rebuilt geometry must pass another native approach check before commitment.

Fresh queries use the original synchronous physics API. Endpoints and the chosen hit must stay within 1.5 horizontal units of the current native mover, with bounded vertical displacement and a forward-direction check. After collision and exit validation, the local result is temporarily exposed and the phase becomes 2. The original driver runs with zero delta time, preserving its own eligibility, final validation and start logic.

## Bounded assistance

A fresh manual press creates a 1.25-second candidate-search window. Merely pressing climb makes no movement or settings change. Two mutually exclusive modes are available.

| Mode | Candidate requirement | Temporary changes |
| --- | --- | --- |
| Higher top | Grounded; top 0.5-2.5 units above the native mover; original angle threshold; valid motion, reach and exit | Local ground-climb height from 1.95 to 2.5 |
| Steep surface | Valid candidate up to 65 degrees within the original height; native motion, reach and exit checks | Local slide entry 65 degrees, exit 60 degrees, character slope support up to 65 degrees; walking cap only after native climbing starts |

The higher search starts above its accepted ceiling with room for the collision box thickness and its horizontal footprint on a permitted sloped top. It may discover a higher top after the original low approach rejects, but the engine still reruns its own approach/headroom pipeline after any height allowance. Its raised hit is never injected into the controller. Air-climb height and movement speed stay unchanged in this mode.

Steep support is limited to three horizontal and three vertical game units from activation. Climbing has an eight-second bound. Supported steep ground within that area can retain assistance; flat ground ends it after 0.35 seconds, lost support after 0.25 seconds. Leaving the area, incompatible states, identity changes or conflicting settings changes also end assistance. A lower preexisting speed cap is respected. The separate 70-degree support/contact limit remains untouched.

Settings are resolved through the per-avatar override map. If no override exists, the original modifier routine receives an empty descriptor and may create an engine-owned 852-byte local copy and its registry entries. Shared templates are never modified. Native destruction retains ownership of those records.

## Write footprint and native calls

The query path temporarily writes at most 120 bytes: one 44-byte selected hit, up to nine eight-byte unit/actor pairs and a four-byte phase. Steep assistance adds at most 16 bytes across four local fields; higher-top mode instead adds four bytes. The maximum direct footprint is 136 bytes. Engine-owned override creation has separate allocation/registry effects.

| Existing function | Relative virtual address |
| --- | --- |
| Actor validity / flags / motion | EXE 0x79c290 / 0x79e320 / 0x79e490 |
| Mover lookup / position / dimensions | EXE 0x7d3280 / 0x7d40b0 / 0x7d4e70 |
| Direction/up basis / quaternion | game.dll 0x1490a30 / 0x148c030 |
| Native approach detector | game.dll 0xa8a710 |
| World ID / synchronous shape query | EXE 0x7a48f0 / 0x7fe0a0 |
| Exit classification / original local driver | game.dll 0xa8b8a0 / 0xa883f0 |
| Local settings override creation | game.dll 0x832d40 |

Both module hashes, live physics/mover bindings and selected function entry bytes are checked. Native SIMD buffers are aligned. Exit results 3 and 4 qualify; 5 rejects. This validator is not a full swept-animation trajectory guarantee.

## Diagnostics and verification

The local heartbeat writes at most every two seconds during normal updates and flushes on terminal paths. `native_starts` counts immediate climbing-state entries after retries, not completed traversals. `step_report_retries/starts` describe retries while the retained automatic-step report is set. `context_reprojections` counts private geometry rebuilds; `reprojected_retries/starts` track their native retries and entries. `last_retry_reason` records the last consumed-query outcome.

Candidate and probe diagnostics retain the last search outcome, limits, returned heights/normals, motion and exit results, plus age and native mover origin. They can describe an earlier position; inspect age and position before attributing a trace. Logs remain local and are excluded from source control and packages.

Tests exercise the actual Lua snapshot/patch logic against bounded synthetic allocations, including a separate remote avatar, identity changes, query reuse, input release, native-check rejection, retained step reports, changed approaches, rollback and cleanup. Forty native geometry fixtures retain independent expected float results while using synthetic ownership addresses and unit identifiers. Rebuilt geometry matches the expected source/size/target floats; basis comparisons allow the native quaternion roundtrip's floating-point difference.

Native physics, override creation and driver calls are modeled in behavioral tests. Offline checks do not prove live traversal or host/client acceptance. The current retained-report and geometry recovery paths still require in-game confirmation. Shared-loader/startup checks exercise integration separately from gameplay and rendering. Build and audit instructions are in [CONTRIBUTING.md](../CONTRIBUTING.md).
