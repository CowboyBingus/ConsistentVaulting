# Local vault query processing

The implementation uses the existing Lua resource packaging and shared-loader API. Resource `mods/cowboybingus/consistent_vaulting` belongs only to this gameplay package; Bingus Shared Loader loader-v4 discovers it before the supported overlay module. The loader's manager GUID and API 1 remain unchanged.

The original proposed control-flow fix is implemented through candidate data: earlier unusable hits are hidden from the existing selector, and a physically validated metadata fallback uses the selector's existing no-actor representation in that local query. No global actor flags or native instructions change.

## Scope and writes

The player manager at game.dll global RVA `0x276c190` supplies the local player's unit reference. The entity-owner and avatar-manager maps resolve its current avatar and controller; index zero and ownership alone are never used to select a target. Mission state, resource identity, ownership, registry equality, controller entity ID, and current manual input must agree.

Data-v2 supports stage 2 and the consumed stage 3. Every descriptor must point into the resolved controller, use the verified filter/type, ignore the correct avatar engine unit, and have one-result capacity. Stage 2 requires a completed enclosing worker range. Stage 3 requires a zero scheduler count and all eight worker completion flags set. Retained descriptors remain bounded to 2,048 slots and must individually match the local controller; a zero count alone does not establish ownership. Query records and job ranges are rechecked before writes.

The original stage-2 path writes eight-byte unit/actor pairs at `controller + 0x4c + slot * 44`. The stage-3 retry can write one freshly cast 44-byte hit, clear the unit fields of the other nine hits, and temporarily change the four-byte phase from 3 to 2. The maximum direct write footprint is 120 bytes, all within the resolved local controller. Query IDs, scheduler records/counts, shared actor flags and settings are never written. The Windows adapter requires existing committed `MEM_PRIVATE / PAGE_READWRITE` storage. The original native routine owns subsequent animation/state changes.

Original bytes are retained while the query epoch remains current. Stage-2 edits are restored before reevaluation; stage-3 edits are restored immediately after the native retry. The late epoch excludes the intentionally changed phase but includes local identity, query IDs, descriptors and idle worker data. A changed entity or reused query is never restored by stale address. Failed or partial writes stop processing and attempt restoration within that epoch. Shutdown and original-update exceptions also attempt restoration. Snapshot checks are not a general synchronization primitive; native/Lua scheduling and teardown must be exercised in-game.

## Candidate policy

The module prefers the first candidate that passes the normal surface test, actor motion limit, current ground/air height allowance, and native exit validation without the manual metadata veto. It considers a vetoed candidate only if no such candidate succeeds. It does not relax surface angle, motion or height values. A working first candidate requires no write.

The effective AvatarComponent record is resolved through its per-avatar override map, with a checked resource-level fallback. Settings are read only. The motion and height comparisons retain float32 rounding. Automatic input alone cannot commit an edit. During active manual input, the lower native automatic-step prepass also sees the prepared candidate; the game retains its normal decision between stepping and vaulting.

## Consumed-query retry

The late path first checks the original A88020/A88160 state masks and rejects existing climbing/step readiness. While manual input remains active it attempts at most ten retries per second. It copies the controller into private aligned storage, sets only that copy to stage zero and calls the original approach detector with zero dt. The detector must produce stage 1 and all eleven approach-geometry floats must remain within 0.02 of the retained batch. This preserves the original approach search when the player moves, turns or encounters changed collision.

Previously nonempty local query slots are then cast synchronously into private buffers using the original worker descriptor layout, filter, shape/type, ignored unit and one-hit capacity. Previously empty slots are excluded because native result counts are preserved. Query endpoints and the selected hit must remain within 1.5 horizontal units of the current mover, with conservative vertical and forward bounds. These are additional stale-data guards; the original approach, height, normal, motion and exit checks still apply.

After snapshot rechecks, one fresh validated hit is exposed, other hit units are hidden and the phase is temporarily set to 2. Calling the original local driver at `0xa883f0` with zero dt preserves its eligibility, selection, final exit validation and start routine without advancing movement timers a second time. Original query bytes are restored afterward. No readiness or animation bit is forced directly. An observed new native climbing bit increments `native_starts`; this measures state entry, not completion or network acceptance.

## Existing native validation calls

Unlike the simplest data-setting mods, this module calls existing game functions through LuaJIT FFI. It creates no native callback, DLL, executable allocation, or instruction patch. These calls are not mocked in production:

| Function | RVA |
| --- | --- |
| Actor validity / flags / motion vectors | EXE `0x79c290`, `0x79e320`, `0x79e490` |
| Local mover lookup / position / dimensions | EXE `0x7d3280`, `0x7d40b0`, `0x7d4e70` |
| Direction/up basis and quaternion extraction | game.dll `0x1490a30`, `0x148c030` |
| Exit and route classification | game.dll `0xa8b8a0` |
| Approach detector on private controller copy | game.dll `0xa8a710` |
| World ID / synchronous physics query | EXE `0x7a48f0`, `0x7fe0a0` |
| Original local eligibility/check/start driver | game.dll `0xa883f0` |

The runtime verifies both supported module hashes, live physics/mover API bindings, and the exit validator entry bytes. SIMD buffers are explicitly aligned. RCX is unused by the captured exit validator; RDX receives the resolved local avatar entity, R8 the candidate position, and R9 its orientation. Only results 3 and 4 qualify; 5 rejects. The original engine subsequently runs its own final validation and animation path.

The worker lifecycle was traced in `0x14acf80` and `0x14acdc0`: eight ranges at scheduler `+0x40004`, each holding start/end/done, and 128-byte query records with clamped result count at `+0x76`. Matching a completed range plus a nonempty freshly populated hit avoids treating a submitted empty result buffer as usable. Query/job consistency is checked again before edits.

## Validation and limits

Tests use the real Lua snapshot reader and writer against bounded synthetic allocations, including a remote avatar at index zero and local avatar at index one. They cover preferred alternatives, metadata fallback, automatic-only input, motion/height/exit rejection, worker completion, pointer/identity mismatch, mission transitions, input release, buffer reuse, failed/partial writes, restoration and real Windows memory permissions. Startup tests cover build/loader gates, callback tuples, shutdown, exceptions and failure isolation. Package tests verify sole resource ownership, dependency metadata, hashes and absence of executable payloads.

Native physics calls are mocked in the behavioral fixtures; their successful execution inside the game is **not** established by passing offline tests. During the September 12 mission capture, 17,410 external samples included 15,633 stage-3 samples, 1,727 stage-1 samples and only 50 stage-2 samples. Manual input was active in 4,305 samples; data-v1 logged no observed queries. A later read-only snapshot confirmed stage 3, scheduler count zero, all workers complete and ten retained descriptors still owned by the local controller. This supports the new integration point but does not validate executing the revised native calls in-game.

The runtime log now refreshes every two seconds even when status is unchanged. `updates`, `polls`, phase counters, `fresh_queries`, `retry_calls` and `native_starts` distinguish callback liveness, accepted snapshots, collision refreshes, retry invocation and observed climbing-state entry. Terminal failures and shutdown flush immediately.

Before promoting data-v2, test manual vaults against ordinary, flagged, beveled, obstructed, moving and excessive-height obstacles; confirm animation and unsupported landings still behave correctly. Then test death/reinforcement, mission transitions, and both hosting and joining with an unmodified teammate. Check that the teammate's own vault behavior remains unchanged and that the host does not correct the local player's traversal. This package is an offline-verified gameplay candidate, not a gameplay-verified release.
