# Implementation and validation

## Supported runtime

The module is locked to Steam build 25480438 / EXE 1.8.46015.0 and the module hashes in `scripts/archive.py`. It loads as `mods/cowboybingus/consistent_vaulting` through Bingus Shared Loader; it requires v18 or newer (v19 is current), and its own load check accepts loader-v4 / API 1 or newer. The resource name and mod-manager GUID are compatibility identifiers.

The package supplies stripped LuaJIT bytecode. It invokes existing engine functions through FFI and uses existing writable private data. It installs no custom DLL, executable-memory allocation, instruction patch or protection change. Memory reads, protection checks, writes and module hashes come from `src/bingus_runtime.lua` v1, a byte-identical copy of the shared CowboyBingus runtime: it declares every Windows function under private, versioned names and reads each module's hash once per session for every mod that uses it.

## Local ownership and lifetime

The player manager supplies the local unit reference. Entity and avatar maps resolve the controller, effective settings and mover. Mission state, entity resource, ownership, registry equality, controller identity and manual input must agree. Index zero is not assumed to identify the local player.

Completed stage-2 queries and retained stage-3 queries are supported. Every descriptor must point into the resolved local controller, use the expected filter/type, ignore the correct avatar, and have one-hit capacity. Stage 3 requires an idle scheduler and all eight workers complete. Reused descriptors are excluded from native consumption; unavailable snapshots are skipped.

Data-v8.6 retains private templates for reused query slots and fixes a circular dependency found in the installed v8.5 test: higher-top discovery required the ordinary-height approach to succeed before it could build geometry. When that approach rejects, a grounded manual attempt can run the native five-slice geometry helper with a private 2.5-height parameter block. Its root and dimensions come from the current native mover, its reach from the current effective avatar settings, and its direction from the existing validated input path. The helper writes only private outputs; neither real settings nor scheduler records change during discovery. All ten downward shapes use fresh geometry and one-hit private storage. Missing, malformed or out-of-reach results reject assistance. Foreign descriptors and their hit counts are never trusted or written.

These rebuilt queries are discovery-only. The native selectors at game.dll +0xA9E450 and +0xA9E650 still read capacity/result counts from the shared scheduler. They must not consume a controller whose IDs now refer to unrelated records. A valid private candidate can enable the existing local slope/height allowance; normal native frame processing performs the climb. The direct retry retains its original ownership requirements.

Writes are guarded by the original entity/query epoch and byte values. Stage-2 edits are restored before reevaluation; stage-3 edits are restored immediately after the original native retry. Changed identity or reused storage prevents restoration by stale address. Failed or partial writes attempt rollback. Shutdown and original-update exceptions use the same cleanup.

The update chain is the runtime's guard. The game's update runs outside pcall, so its errors reach the engine unchanged. After such an error the mod restores its edits, resets to a fresh start and pauses; it resumes once the updates below have returned on 60 frames in a row. Its own errors restore and reset the same way and are counted. Eight errors below it, or eight of its own, in one burst (a burst ends after 3,600 error-free frames), a refusal or a restore that fails stop it for the session; the first failure survives shutdown.

## Manual candidate selection

Fresh candidates must pass the current surface-angle threshold, actor-motion limit, ground/air height allowance, reach and native exit validation. An eligible candidate without the manual metadata veto is preferred. Otherwise, one validated fallback uses the native selector's existing no-actor representation only in that local query result. Shared obstacle flags are unchanged.

The existing climbing state, pending readiness at controller +532 and the original A88020/A88160 eligibility masks prevent a retry. Controller +533 reports an automatic step; it can remain set when a later lower-candidate search finds nothing. The native manual eligibility routine does not use that report as a veto. The mod preserves it without directly setting or clearing it.

During active manual input, stage-3 retries run at most ten times per second. Only previously nonempty slots can supply a refreshed result for consumption because native result counts remain unchanged. The original automatic-step prepass also sees the selected result; the engine owns the choice between stepping and vaulting.

## Fresh approach geometry

A private aligned controller copy enters stage zero and runs the original approach detector with zero delta time. Controller consumption requires a successful stage-1 approach.

When any of the eleven geometry floats differs by more than 0.02 game units from the retained batch, the mod reconstructs private descriptors using the recovered native producer formula. It validates identity, finite dimensions and the native horizontal forward/up basis. Ten source positions interpolate between the approach endpoints; each box uses half the native width, one twentieth of the endpoint separation, and 0.05 vertical half-extent. Sweep endpoints follow the native vertical span and offsets with float32 rounding.

Only private matrix/translation, dimensions and sweep targets change. The scheduler, real controller geometry, output ownership, filters, ignored unit and capacity are preserved. Ordinary rebuilt geometry must pass another ordinary native approach check before commitment. Independent higher geometry repeats its own native search and must agree within 0.02 units before any height allowance.

Fresh queries use the original synchronous physics API. Endpoints and the chosen hit must stay within 1.5 horizontal units of the current native mover, with bounded vertical displacement and a forward-direction check. After collision and exit validation, the local result is temporarily exposed and the phase becomes 2. The original driver runs with zero delta time, preserving its own eligibility, final validation and start logic.

## Bounded assistance

A fresh manual press creates a 1.25-second candidate-search window. Merely pressing climb makes no movement or settings change. Two mutually exclusive modes are available.

| Mode | Candidate requirement | Temporary changes |
| --- | --- | --- |
| Higher top | Grounded; top 0.5-2.5 units above the native mover; original angle threshold; valid motion, reach and exit | Local ground-climb height from 1.95 to 2.5 |
| Steep surface | Valid candidate up to 65 degrees within the original height; native motion, reach and exit checks | Local slide entry 65 degrees, exit 60 degrees, character slope support up to 65 degrees; walking cap only after native climbing starts |

The higher search starts above its accepted ceiling with room for the collision box thickness and its horizontal footprint on a permitted sloped top. It may discover a higher top after the original low approach rejects, but the engine still reruns its own approach/headroom pipeline after any height allowance. Its raised hit is never injected into the controller. The independent discovery helper does not reproduce the detector's preliminary overlap and upward-clearance stages; the real native detector still performs those stages after any temporary height allowance. Air-climb height and movement speed stay unchanged in this mode.

Steep support is limited to three horizontal and three vertical game units from activation. Climbing has an eight-second bound. Supported steep ground within that area can retain assistance; flat ground ends it after 0.35 seconds, lost support after 0.25 seconds. Leaving the area, incompatible states, identity changes or conflicting settings changes also end assistance. A lower preexisting speed cap is respected. The separate 70-degree support/contact limit remains untouched.

Settings are resolved through the per-avatar override map. If no override exists, the original modifier routine receives an empty descriptor and may create an engine-owned 852-byte local copy and its registry entries. Shared templates are never modified. Native destruction retains ownership of those records.

## Write footprint and native calls

The query path temporarily writes at most 120 bytes: one 44-byte selected hit, up to nine eight-byte unit/actor pairs and a four-byte phase. Steep assistance adds at most 16 bytes across four local fields; higher-top mode instead adds four bytes. The maximum direct footprint is 136 bytes. Engine-owned override creation has separate allocation/registry effects.

| Existing function | Relative virtual address |
| --- | --- |
| Actor validity / flags / motion | EXE 0x7972f0 / 0x7993d0 / 0x799540 |
| Mover lookup / position / dimensions | EXE 0x7ce220 / 0x7cf050 / 0x7cfe10 |
| Direction/up basis / quaternion | game.dll 0x173f080 / 0x173a680 |
| Native approach detector | game.dll 0xa9c3e0 |
| Native private five-slice geometry helper | game.dll 0xa9dd90 |
| World ID / synchronous shape query | EXE 0x79f860 / 0x7f9070 |
| Exit classification / original local driver | game.dll 0xa9d560 / 0xa9a0c0 |
| Local settings override creation | game.dll 0x83c420 |

Both module hashes, live physics/mover bindings and selected function entry bytes are checked. Native SIMD buffers are aligned. Exit results 3 and 4 qualify; 5 rejects. This validator is not a full swept-animation trajectory guarantee.

## Per-frame cost and garbage

### Design: allocation-free held vault and no-avatar checks

Idle checks (outside a mission, idle in a mission, a retained query with the input released) allocate nothing. Two per-frame states still create Lua garbage, measured offline in the game's lua51.dll with the runtime's memory API on real memory, a fixture clock and fixture natives, after a warm-up:

| State | Checks per frame | Garbage per frame (compiled / interpreted) |
| --- | --- | --- |
| Vault input held on a complete stage-2 query, prepared edit kept | 2 | 50.6 KB / 75.7 KB |
| In a mission without a local avatar (dead, respawning) | 1 | 0.64-1.9 KB, 1.15 KB with no unit reference |

Cost statement, per frame (calls x in-game cost):

- Without a local avatar: 8 to about 30 ReadProcessMemory (`read` and `read_into`, about 1-2 us each in game), depending on where the identity chain stops; no VirtualQuery, no write, no native call. Unchanged.
- Held stage-2 vault: 446 ReadProcessMemory (406 `read`, 40 `read_into`: about 0.45-0.9 ms in game), no VirtualQuery and no write. Per check two mover positions (3 native calls and 1 ReadProcessMemory each), up to two actor checks (4 native calls each) and two exit validations (3 native calls each), unmeasured in game, and one clock read. Unchanged.
- `api.pointer` and `api.distance` (Lua only, no system call) are no longer called on these paths, because pointers decode in place; their budget pins drop. Every other call keeps its address, size, order and pin.
- Garbage: target 0 B per frame in both states, interpreted and compiled, in both VMs, pinned in `tests/test_slope.lua` next to the idle pins. Expected leftovers with the real adapter, interpreted code only: the 16-byte box the interpreter makes for a native function's 64-bit or pointer result (actor validity twice per actor check, the mover dimensions per mover position, the basis routine per exit validation) and the v1 clock's 64-bit count. Compiled code does not box them (measured with kernel32 functions of the same return types in both VMs).
- `api.read` returns a string; LuaJIT interns strings, so re-reading unchanged bytes returns the kept string. Bytes that changed since the last check still make one new string per changed read: in play likely the camera direction, the mover and movement records and possibly the controller while the player moves, up to about 1 KB per check (unmeasured in game).
- Compiled code: the per-check helpers stay compiled and rarely run paths interpreted; expected within 10 KB of today's 55 KB per session (median of 10 processes in the game's lua51.dll), measured after each step.

Pinned reads per check (2026-10-04, `tests/test_slope.lua` and `tests/test_vault.lua`, offline fixtures; `read` + `read_into`, about 1-2 us each in game; protection queries unchanged):

| Scenario | Before | After |
| --- | --- | --- |
| Outside a mission | 4 | 2 |
| Idle in a mission, or a retained query with the input released | 19 | 7 |
| Input held, no new press | 48 | 45 |
| Input held on a retained query (vault snapshot runs) | 72 | 52 |
| Assist armed (press check) | 165 | 163 |
| Assist held / climb held | 47 | 44 |
| Vault-only: held query edit kept | 176 | 94 |

The idle check verifies the kept identity (the input at the kept avatar index, the mission, the unit reference, the entity record at its kept address and the registry slot at its kept index) and resolves the whole chain on any difference or press. The vault snapshot takes the identity chain, and its guards and epoch guards, from the slope snapshot of the same check. A kept vault edit does not read the snapshot's guards a second time; commits and restores still verify them before writing.

Design:

1. Reused records. Each state gets its own snapshot records (a weak table keyed by the state): two vault records used in turn, because a kept edit holds the previous check's record as its epoch; one for the candidate search; one for each check's slope snapshot. A record holds its guard records (address, bytes, view) and ten hit records, and a refill resets every field. A snapshot compared with another one of the same check, or kept (a lease release, the snapshot after override creation, direct calls), gets a fresh record as before.
2. Numbers inside, api addresses outside. Addresses are Lua numbers inside the snapshots and reach the api as its own address values, made once per address, as the light reads do. Pointers decode in place with `api.pointer`'s rule, hash products from 16-bit halves, fields from the bytes with `string.byte`, floats through one union cell: no `ffi.cast` or 64-bit cdata per field.
3. Copies where data leaves a check: a lease's key and anchor, a press window's key, a candidate trace's root, direction and hit positions. The native helpers return numbers (mover position: x, y, z; actor: valid, flags, motion) and reuse their buffers.
4. One reused plan record per check. A held edit is kept by comparing that plan with the held writes as numbers; only a new edit builds write records and byte strings, and a kept edit's pending record is updated in place.
5. A held hit or controller is restored into one reused buffer. Its guard keeps both the bytes read and the restored view, so unchanged memory finds the same strings.
6. Cognitive complexity: `M.plan`, `assist_candidate`, `M.refresh` and `M.reproject` become named steps of 15 or less; the rarely run ones stay interpreted.

Each step is checked with a differential against the previous commit over generated frames (every api and native call with its arguments and results, writes, printed lines, log files, state and memory identical; `api.pointer` and `api.distance` compared only in steps that keep them), mutation checks, and compiled code measured in the game's lua51.dll.

## Diagnostics and verification

The local heartbeat writes at most every two seconds during normal updates and flushes on terminal paths. `native_starts` counts immediate climbing-state entries after retries, not completed traversals. `step_report_retries/starts` describe retries while the retained automatic-step report is set. `query_rebuilds` counts discovery batches rebuilt after shared slot reuse. `context_reprojections` counts private geometry rebuilds; `reprojected_retries/starts` track their native retries and entries. `last_retry_reason` records the last consumed-query outcome.

Candidate and probe diagnostics retain the last search outcome, limits, returned heights/normals, motion and exit results, plus age and native mover origin. They can describe an earlier position; inspect age and position before attributing a trace. Logs remain local and are excluded from source control and packages.

Tests exercise the actual Lua snapshot/patch logic against bounded synthetic allocations, including a separate remote avatar, identity changes, query reuse, input release, native-check rejection, retained step reports, changed approaches, rollback and cleanup. Forty native geometry fixtures retain independent expected float results while using synthetic ownership addresses and unit identifiers. Rebuilt geometry matches the expected source/size/target floats; basis comparisons allow the native quaternion roundtrip's floating-point difference.

Native physics, override creation and driver calls are modeled in behavioral tests. Offline checks do not prove live traversal or host/client acceptance. The current retained-report and geometry recovery paths still require in-game confirmation. Shared-loader/startup checks exercise integration separately from gameplay and rendering. Build and audit instructions are in [CONTRIBUTING.md](../CONTRIBUTING.md).

Installed v8.5 evidence: 46 of the first 48 checks returned fresh_approach_unavailable, with the other two out of reach and no raised casts. The v8.6 regression reproduces reused slots plus a blocked low approach; the old source fails and the repaired source passes. Adapter tests verify the native parameter layout, refreshed mover origin, private output packing and invalid-geometry rejection. Vaulting, slope and ledge assists were later confirmed in live play (v8.8).
