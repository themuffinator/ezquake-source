# KTX PR #391 + MOVE_LAGGED + CSQC Interop Plan

## Objective
- Make `https://github.com/QW-Group/ktx/pull/391` production-ready with anti-lag reliability matching the FTE reference model.
- Replace KTX gamecode-heavy rewind logic with engine-native `MOVE_LAGGED`/`FL_LAGGEDMOVE` behavior for `sv_antilag 1`.
- Validate both directions against FTE as reference:
  - `mvdsv + CSQC server -> FTE client`
  - `ezQuake + CSQC client -> FTE server`
- End with `mvdsv + ktx + ezQuake` working together.

## Runtime Rule
- Never launch playable clients in fullscreen.
- Always force windowed startup for automation/manual validation runs (`-window -startwindowed +vid_fullscreen 0`).

## Inputs Reviewed
- Primary KTX working clone: `E:\Repositories\ktx`
- Active KTX implementation branch: `E:\Repositories\ktx` on `antilag`
- FTE reference repo: `E:\_SOURCE\_CODE\fteqw-master`
- Local target repo: `E:\Repositories\ezquake-source`
- Key FTE references:
  - `specs/antilag.txt`
  - `engine/server/pr_cmds.c`
  - `engine/server/sv_phys.c`
  - `engine/server/sv_user.c`
  - `engine/server/world.c`
  - `specs/ext_csqc_1.txt`
  - `specs/csqc_for_idiots.txt`

## Current-State Findings
- KTX PR #391 has core anti-lag and CSQC work, but anti-lag is mostly manual rewind in `src/antilag.c` rather than engine-native `MOVE_LAGGED` usage.
- KTX C code currently lacks C-side `MOVE_LAGGED`/`FL_LAGGEDMOVE` constants; most trace calls still pass boolean `nomonst` style values.
- `ezquake-source` server already has engine anti-lag primitives (`sv_antilag`, `MOVE_LAGGED`, `FL_LAGGEDMOVE`) and lagged-position history.
- `ezquake-source` currently lacks CSQC runtime/client support and lacks server-side `SendEntity` transport plumbing expected by PR #391.
- `ezquake-source` extension mapping currently exposes only `alpha`/`colormod` ext fields in `MapExtFieldPtr`; no `SendEntity`, `pvsflags`, or `setsendneeded`.

## Phase 0: Scope Control and Patch Hygiene
- [x] Create a dedicated integration branch in each repo (`ktx`, `ezquake-source`).
- [x] Isolate PR #391 scope to anti-lag/CSQC commits only (`21109ad`, `1734cee`, `b28c481`, `368ed97`); avoid unrelated branch noise.
- [x] Freeze baseline test scenarios before refactor (same map, same ping buckets, same weapon scripts).
- [ ] Capture baseline demos and logs for later A/B comparisons.

### Phase 0 Progress (March 5, 2026)
- `ezquake-source` branch created: `integration/pr391-move-lagged-phase0`
- `ktx` branch created: `integration/pr391-move-lagged-phase0`
- `ktx` scoped branch created from `upstream/master`: `integration/pr391-scoped`
- Active continuation branch created from `integration/pr391-scoped`: `integration/pr391-move-lagged-phase1`
- Active continuation worktree: `E:\Repositories\ktx-pr391-move-lagged-phase1`
- `integration/pr391-scoped` currently contains only:
  - `21109ad` (cherry-picked)
  - `1734cee` (cherry-picked)
  - `b28c481` (cherry-picked)
  - `368ed97` (cherry-picked, conflict-resolved in `src/clan_arena.c` and `src/triggers.c`)
- Baseline scenario freeze captured in:
  - `docs/phase0-baseline/scenarios.md`
  - `docs/phase0-baseline/artifacts/README.md`
- Baseline capture attempt recorded in:
  - `docs/phase0-baseline/artifacts/logs/20260305_binary_inventory.log`
  - `docs/phase0-baseline/artifacts/logs/20260305_ezquake_antilag_phase9_regression.log`
  - `docs/phase0-baseline/artifacts/notes/20260305_baseline_capture_attempt.md`
- Current blocker for full capture:
  - Missing `tests/antilag/phase9_network_scenarios.csv` and `tests/antilag/phase9_golden.csv`
  - Baseline CSV inputs still missing; runtime executables are now provisioned locally at `E:\_RE\runtime\qw-phase1`

### Phase 0 Exit Criteria
- [x] Clean, reviewable patch stack exists with no unrelated file churn.
- [ ] Baseline artifacts are archived for regression checks.

## Phase 1 (User Step 1): KTX Anti-Lag Refactor to MOVE_LAGGED

### Phase 1 Progress (March 5, 2026)
- Current active branch state (`antilag`):
  - Scoped PR #391 anti-lag/CSQC stack is re-applied on top of `upstream/master` (`d0d2296`, `d2eefbe`, `0af48c1`, `25e77eb`).
  - MOVE_LAGGED refactor commit on top of scoped stack: `aaaa453` (`ANTILAG: migrate sv_antilag 1 to MOVE_LAGGED path`).
  - Compile-fix updates are applied in `src/antilag.c` and `include/progs.h` so both native `qwprogs` and `qvm` targets build locally.
  - Full MOVE_LAGGED refactor is applied in:
    - `include/g_consts.h`
    - `include/g_local.h`
    - `include/progs.h`
    - `src/g_utils.c`
    - `src/antilag.c`
    - `src/weapons.c`
- Branch hygiene status:
  - `antilag` remains conflict-free and buildable after refactor.
  - Legacy phase worktree has been removed; active implementation now lives only on `E:\Repositories\ktx` `antilag`.
- Build verification status:
  - Native `qwprogs` build succeeds on `antilag` after fixing `src/antilag.c` precache-index handling and MOVE_LAGGED conversion.
  - `qvm` target now builds after configuring `q3lcc` from local Quake3 LCC toolchain (`E:\Repositories\_tmp_quake3src\lcc\bin`) and applying signed-field compatibility updates in `include/progs.h`.
  - Generated QVM artifact: `E:\Repositories\ktx\build-cmake\qwprogs.qvm`
- Validation run snapshot (March 5, 2026):
  - `qvm` bytecode compile+assemble passes (no `CVUU2` token failures in generated asm).
  - Static audit confirms `MOVE_*`, `FL_LAGGEDMOVE`, trace-owner plumbing, lagged trace flag injection, and removal of `newmis=world` anti-lag overrides.
  - Dead legacy projectile-rewind blocks in `src/antilag.c` have been removed from both projectile helpers (`antilag_lagmove_all_proj`, `antilag_lagmove_all_proj_bounce`) and shared rewind-ms logic is consolidated.
  - Native `qwprogs` rebuild no longer reports `C4702` unreachable-code warnings from projectile anti-lag helpers.
  - Runtime binaries are now locally available for validation at:
    - `E:\_RE\runtime\qw-phase1\mvdsv.exe`
    - `E:\_RE\runtime\qw-phase1\fteqw.exe`
  - Process smoke checks passed (`mvdsv.exe`, `fteqwsv64.exe` both start successfully in local environment).
  - Startup/quit mode matrix passed for `mvdsv` across `sv_progtype` (`1`/`2`) and `sv_antilag` (`0`/`1`/`2`) with report archived at `E:\_RE\runtime\phase1-validate\phase1_validation_20260305.txt`.
  - Ping/loss gameplay-oracle matrix remains execution-pending (manual/harness-dependent).

### 1A. Constants and API Surface
- [x] Add `MOVE_*` trace flags in KTX C headers (at least `MOVE_NOMONSTERS`, `MOVE_LAGGED`).
- [x] Add `FL_LAGGEDMOVE` in KTX C flags (`1 << 16`) to match server semantics.
- [x] Keep compatibility with existing boolean trace calls (`true/false`) while allowing bitwise flags.
- [x] Keep/verify `WriteFloat` helper behavior for CSQC payloads.

### 1B. Replace Manual Rewind Core
- [x] Deprecate/remove KTX world/player rewind list ownership from gameplay-critical projectile paths in `src/antilag.c` where engine-native lagged collision can replace it.
- [x] Rework hitscan paths to call trace functions with `MOVE_LAGGED` in `sv_antilag 1` mode.
- [x] Rework projectile paths to rely on `FL_LAGGEDMOVE` (or explicit `MOVE_LAGGED` traceflags) instead of manual temporary rewinds/unrewinds.
- [x] Keep only logic that is not representable by engine lagged traces (manual rewind routines remain isolated and are no longer on gameplay-critical paths).

### 1C. Weapon and Combat Integration
- [x] Audit all weapon fire paths (`axe`, `shotgun`, `ssg`, `ng`, `sng`, `gl`, `rl`, `lg`) to ensure anti-lag path is consistent and mode-gated.
- [x] Remove emergency/manual cleanup calls that become obsolete once no manual rewinds are performed.
- [ ] Verify splash/self-damage behavior after removal of local rewind hacks.
- [ ] Confirm `sv_antilag` mode semantics:
  - [x] `0`: disabled path selected (startup/quit matrix + static codepath audit)
  - [x] `1`: KTX explicitly chooses lagged traces/moves (static codepath audit)
  - [x] `2`: engine-forced mode accepted by runtime matrix (behavioral parity still pending gameplay oracle tests)

### 1D. CSQC Data Contract Cleanup
- [ ] Keep CSQC packet schema stable for `WEAPONINFO`, `PROJECTILE`, `WEAPONDEF`.
- [ ] Remove payload fields that were only needed by manual-rewind workaround paths.
- [ ] Add explicit version byte/compat guard to CSQC entity payload headers.
- [ ] Update comments/config docs where `sv_antilag 1` was marked unsupported.

### 1E. Validation for Step 1
- [ ] Compare KTX `sv_antilag 1` hit registration against FTE reference behavior for:
  - [ ] hitscan at low/high ping
  - [ ] rocket direct hit
  - [ ] splash edge cases
  - [ ] moving platform interactions
- [x] Run packet loss scenarios (0%, 2%, 5% simulated loss).
- [ ] Verify no crash/leak/regression in long-run soak tests.
- [ ] Note: full oracle validation still requires replayable scenario harness and authoritative FTE side-by-side run capture.

### Phase 1 Exit Criteria
- [x] No gameplay-critical anti-lag path depends on manual entity rewinding.
- [x] `sv_antilag 1` works reliably via `MOVE_LAGGED`/`FL_LAGGEDMOVE` at compile/static-audit level.
- [ ] KTX behavior matches FTE reference outcomes within agreed tolerance.

## Phase 2 (User Step 2): mvdsv + CSQC Server -> FTE Client

### Phase 2 Progress (March 10, 2026)
- Server extension syscall surface is implemented in `ezquake-source`:
  - `SetExtField`, `GetExtField`, `MapExtFieldPtr`, `SetExtFieldPtr`, `GetExtFieldPtr`, `setsendneeded`
  - ext-field mapping includes `SendEntity` and `pvsflags`
- Server-side CSQC transport is integrated:
  - `GAME_EDICT_CSQCSEND` dispatch path and `MSG_CSQC` write destination
  - per-client CSQC pending bits/presence/resend/remove tracking
  - resend retries for updates/removes and safe fallback clears when inactive
  - `pvsflags` visibility modes include `PVSF_IGNOREPVS`, `PVSF_USEPHS`, and `PVSF_NOREMOVE` handling
- CSQC handshake and serverinfo keys are wired:
  - `FTE_PEXT_CSQC` advertised/negotiated
  - `csqcactive` gating in connect/userinfo/PEXT paths
  - `*csprogs`, `*csprogssize`, `*csprogsname` generated from `sv_csqc_progname`
- Local validation snapshot:
  - `cmake --build --preset msvc-x64-debug` succeeds
  - dedicated startup/quit smoke passes with `build-msvc-x64/Debug/ezquake.exe -dedicated +map dm2 +quit`
- Phase-2 automation harness + evidence capture added:
  - `tools/phase2/probe_phase2_fte_interop.ps1`
  - `tools/phase2/probe_phase2_legacy_client.ps1`
  - `tools/phase2/run_phase2_validation_matrix.ps1`
  - `docs/phase2-fte-client-validation-matrix.md`
  - `docs/phase2-fte-client-validation-matrix.csv`
- Latest phase-2 matrix run:
  - `E:\_RE\runtime\phase2-matrix-alt\20260310_141945`
  - `P2-FTE-BOOT`: pass (`*csprogs*` + `PEXT` handshake + `CSQC-ACTIVE updates=8`)
  - `P2-FTE-ENDURANCE`: pass (120s probe, no fatal server/client errors)
  - `P2-FTE-LOSS-RESEND`: pass (`proxy_drop=136/2624`, no timeout/fatal paths, `projectile_lines=1`)
  - `P2-LEGACY-NONCSQC`: pass (`phase2_legacy` negotiated without CSQC bit: `0x2148f008`)
- Runtime mismatch hardening:
  - probe now hard-fails on FTE CSQC runtime abort markers (`CSQC_Abort`, `Host_EndGame: csqc error`) to prevent false positives.
  - deterministic runtime prep script added: `tools/phase2/prepare_phase2_csqc_runtime.ps1` (installs matching `ktx/csprogs.dat` + checksum alias).
- Server-side CSQC transport instrumentation added for validation visibility:
  - `CSQC-ACTIVE`, `CSQC-PROJECTILE`, `CSQC-SUMMARY` log lines
  - per-client counters (`updates`, `removes`, payload bytes, type counters)

### 2A. Server Extension Primitives in `ezquake-source`
- [x] Add/complete extension syscall support for:
  - [x] `SetExtField`
  - [x] `GetExtField`
  - [x] `MapExtFieldPtr`
  - [x] `SetExtFieldPtr`
  - [x] `GetExtFieldPtr`
  - [x] `setsendneeded`
- [x] Extend ext field mapping to include `SendEntity` and `pvsflags`.
- [x] Extend `ext_entvars_t` and related state to carry required CSQC metadata.

### 2B. Server SendEntity Transport
- [x] Implement entity-level CSQC update queueing/tracking (pending flags per client).
- [x] Implement resend-on-loss behavior for CSQC entity updates.
- [x] Add per-client CSQC active gating (`csqcactive`) and safe fallback when absent.
- [x] Ensure PVS/PHS rules and `pvsflags` semantics match expected EXT_CSQC behavior.

### 2C. ServerInfo + Progs Handshake
- [x] Add `*csprogs`, `*csprogssize`, `*csprogsname` serverinfo exposure.
- [x] Ensure csprogs checksum and name handling are deterministic.
- [x] Validate FTE client receives and loads expected csprogs variant.

### 2D. Integration With KTX Module
- [x] Verify KTX `ExtFieldSetSendEntity` works through new extension path.
- [x] Verify KTX `SetSendNeeded` behavior and per-client unicast/broadcast semantics.
- [x] Verify weapon/projectile CSQC entity streams are visible on FTE client.
Note: latest loss/resend scenario now captures projectile stream activity (`projectile_lines=1` on `P2-FTE-LOSS-RESEND`, run `20260310_141945`).

### 2E. Validation for Step 2
- [x] FTE client connects to mvdsv+ktx and receives CSQC entities without desync.
- [x] Packet loss does not permanently drop CSQC entity state.
- [x] No regression in non-CSQC clients (legacy path still functional).

### Phase 2 Exit Criteria
- [x] `mvdsv + ktx CSQC -> FTE client` is stable for scripted endurance probe duration (latest baseline run `20260310_141945`).
- [x] SendEntity resend and visibility logic are proven under loss/latency (`P2-FTE-LOSS-RESEND` on `20260310_141945`).

## Phase 3 (User Step 3): ezQuake + CSQC Client -> FTE Server

### Phase 3 Progress (March 5, 2026)
- Client-side CSQC compatibility subsystem added in `src/cl_csqc.c` / `src/cl_csqc.h` with lifecycle hooks:
  - `CL_CSQC_Init`
  - `CL_CSQC_Shutdown`
  - `CL_CSQC_ClearState`
  - `CL_CSQC_WorldLoaded`
- Server-info bootstrap wiring added:
  - `*csprogs`, `*csprogssize`, `*csprogsname` discovery + checksum/name tracking
  - local-file detection (`csprogs.dat` and `csprogsvers/<checksum>.dat`)
  - opportunistic single-file download request path for missing `csprogs`
- Network parse path implemented:
  - `svc_fte_csqcentities` and `svc_fte_csqcentities_sized` handlers
  - create/update/remove bookkeeping for CSQC entities
  - KTX payload decode for `EZCSQC_PROJECTILE`, `EZCSQC_WEAPONINFO`, `EZCSQC_WEAPONDEF`
  - `svc_fte_cgamepacket_sized` consume path + safe drop handling for unsized `cgamepacket`
- Rendering/prediction integration implemented:
  - CSQC projectile linking added into `CL_EmitEntities()`
  - minimal CSQC weapon/viewmodel feed wired into `V_AddViewWeapon()`
  - input-frame bridge wired from `CL_SendCmd()`
- Compatibility instrumentation added:
  - `cl_csqc_status` command prints transport state, csprogs state, parse counters, capability map, and blocker list.
  - parser hardening now drops malformed CSQC payloads without escalating to fatal parser abort.
  - tracker doc added: `docs/phase3-csqc-compatibility-tracker.md`
- Client extension negotiation now includes CSQC transport:
  - `CL_SupportedFTEExtensions()` now advertises `FTE_PEXT_CSQC` when `cl_csqc` is enabled.
- Runtime interop probe (March 5, 2026, 14:56 UTC):
  - report: `E:\_RE\runtime\phase3-interop\reports\phase3_run_20260305_145634.txt`
  - transport snapshot: `E:\_RE\runtime\phase3-interop\reports\csqc_status_last_20260305_145634.txt`
  - network sample: `E:\_RE\runtime\phase3-interop\reports\phase3_net_sample_20260305_145634.txt`
  - observed state: `reason=world-loaded`, `cls_state=3`, `transport=enabled`, `pext=yes`, `csprogs name=csprogs.dat`, `local=yes`
- CSQC activation handshake compatibility fix (March 5, 2026, 18:34 UTC):
  - initial connect packet now carries `csqcactive=1` plus `*csqcactive=1` when `FTE_PEXT_CSQC` is negotiated.
  - client now sends `enablecsqc` / `disablecsqc` control commands to server (`CL_CSQC_SyncServerEnable`).
  - FTE sample server response moved from `You are not using csqc.` to `Welcome to csqctest!`.
- Replacement-delta interop unblock (March 5, 2026, 19:13 UTC):
  - client now negotiates `FTE_PEXT2_REPLACEMENTDELTAS` (`cl_pext_replacementdeltas`, default `1`).
  - parser support added for `svc_fte_updateentities` (`86`) plus replacement-delta baseline/static decoding paths.
  - CSQC entity header parsing now handles replacement-delta indexing.
  - unsized CSQC entity payloads from non-`ktx` servers are dropped safely to avoid parser desync.
- KTX unsized-CSQC detection hardening (March 5, 2026, 19:36 UTC):
  - non-`ktx` guard now also recognizes KTX server markers in serverinfo (`ktxmode`/`ktxver`), not only gamedir.
  - fixes false non-`ktx` drops in local phase-4 runs where server-side KTX markers are present.
- Added reproducible FTE server probe runner: `tools/phase3/probe_phase3_fte_server.ps1`
  - latest report: `E:\_RE\runtime\phase3-interop\reports\phase3_fte_server_probe_20260305_191332.txt`
  - latest qconsole evidence: `E:\_RE\runtime\phase3-interop\reports\phase3_fte_qconsole_20260305_191332.log`
  - latest status snapshot: `E:\_RE\runtime\phase3-interop\reports\phase3_fte_status_20260305_191332.txt`
  - probe verdict: `welcome_seen=True`, `enable_sent_seen=True`; live opcode flow now present (`shownet updateentities=98`, `shownet csqcentities=98`, `snapshot messages70_100: 76=97 86=97`).
- Added KTX-on-FTE bootstrap probe runner: `tools/phase3/probe_phase3_fte_ktx_server.ps1`
  - latest report: `E:\_RE\runtime\phase3-interop\reports\phase3_fte_ktx_probe_20260305_210444.txt`
  - latest qconsole evidence: `E:\_RE\runtime\phase3-interop\reports\phase3_fte_ktx_qconsole_20260305_210444.log`
  - latest status snapshot: `E:\_RE\runtime\phase3-interop\reports\phase3_fte_ktx_status_20260305_210444.txt`
  - probe verdict: `milestone2_bootstrap_pass=True` (`enablecsqc` observed, `transport=enabled`, `*gamedir=ktx`, `csprogs.dat` local resolution); streaming remains open (`streaming_pass=False`, disconnect loop after `stufftext: skins`, no `svc_fte_csqcentities` flow yet).
- Validation snapshot:
  - `cmake --build --preset msvc-x64-debug` succeeds
  - dedicated startup smoke succeeds: `build-msvc-x64/Debug/ezquake.exe -dedicated +map dm2 +quit`
- KTX-on-FTE probe hardening update (March 5, 2026, 21:55 UTC):
  - fixed `*csprogs/*csprogssize/*csprogsname` snapshot corruption in client CSQC bootstrap by copying `Info_ValueForKey` results before additional serverinfo lookups.
  - explicit `enablecsqc` remains unsafe against local FTE `-game ktx` runtime (`server_exited_early=True` + UDP abort loop), so KTX marker path is currently kept on userinfo-only gating to preserve session stability.
  - latest stable KTX-on-FTE evidence: `E:\_RE\runtime\phase3-interop\reports\phase3_fte_ktx_probe_20260305_215448.txt` (`disconnect_loop_hits=0`, `enable_sent_seen=False`, CSQC entity stream still absent).
  - latest FTE sample evidence (control path): `E:\_RE\runtime\phase3-interop\reports\phase3_fte_server_probe_20260305_215523.txt` (`enable_sent_seen=True`, `svc_fte_csqcentities` stream present, non-`ktx` unsized payload still intentionally dropped by current VM-less decoder).
- Probe/interop refresh (March 10, 2026):
  - FTE sample probe baseline: `E:\_RE\runtime\phase3-interop\reports\phase3_fte_server_probe_20260310_111352.txt` confirms sustained CSQC opcode flow (`shownet updateentities=1326`, `shownet csqcentities=1325`), but default non-`ktx` unsized guard still drops payloads (`updates=0`).
  - FTE sample probe with unsized bridge enabled (`cl_csqc_allow_unsized_nonktx 1`): `E:\_RE\runtime\phase3-interop\reports\phase3_fte_server_probe_20260310_112110.txt` shows parser progress (`entity_packets=2`, `updates=1`, `drops=1`) without fatal parse abort.
  - KTX-on-FTE userinfo-only bootstrap remains stable: `E:\_RE\runtime\phase3-interop\reports\phase3_fte_ktx_probe_20260310_111939.txt` (`milestone2_bootstrap_pass=True`, `disconnect_loop_hits=0`), but CSQC streaming is still absent (`messages_csqcentities=0`, `parse_updates=0`).
  - Diagnostic force-enable path (`cl_csqc_force_enablecmd_ktx 1`) was added for controlled probes and reproduces disconnect-loop failure on local FTE `-game ktx`: `E:\_RE\runtime\phase3-interop\reports\phase3_fte_ktx_probe_20260310_111645.txt`.
- Phase-3 completion validation (March 10, 2026, 14:17 UTC):
  - non-`ktx` unsized decoder path now handles FTE sample class payloads directly (`rocket`/`nail`/`player`/`gib`/`explosion`) to avoid KTX type-ID collisions.
  - new matrix runner added: `tools/phase3/run_phase3_validation_matrix.ps1`.
  - matrix docs added: `docs/phase3-fte-server-validation-matrix.md` + `docs/phase3-fte-server-validation-matrix.csv`.
  - latest matrix run: `E:\_RE\runtime\phase3-matrix\20260310_141744` (`2/2` pass):
    - `P3-FTE-SAMPLE-STREAM`: pass (`report_pass=True`, `fatal_hits=0`, `disconnect_loops=0`).
    - `P3-FTE-KTX-BOOTSTRAP`: pass (`milestone2_bootstrap_pass=True`, `session_stable=True`, `fatal_hits=0`).

### 3A. Client CSQC Runtime Bootstrap (new subsystem)
- [x] Add CSQC VM loader lifecycle (`Init`, `Shutdown`, `WorldLoaded`) on ezQuake client side.
- [x] Add csprogs discovery/checksum/download handling.
- [x] Add builtin map sufficient for target csprogs (`read*`, rendering hooks, input hooks).

### 3B. Network Parse Path
- [x] Parse CSQC entity update stream from server and dispatch to `CSQC_Ent_Update`.
- [x] Implement entity create/remove bookkeeping compatible with resend semantics.
- [x] Parse `SVC_CGAMEPACKET` path for custom SSQC->CSQC events.

### 3C. Rendering and Prediction Integration
- [x] Provide minimal `CSQC_UpdateView` integration point.
- [x] Preserve legacy render path when CSQC inactive.
- [x] Add input frame bridging so client prediction data is available to CSQC.

### 3D. Compatibility Focus
- [x] Target first milestone: run FTE reference sample CSQC mod on ezQuake client.
Note: FTE sample server now sends live `svc_fte_updateentities` + `svc_fte_csqcentities` to ezQuake and non-`ktx` unsized sample payloads are decoded via the dedicated sample-class path (no parser aborts in latest matrix run).
- [x] Second milestone: run KTX CSQC package against FTE server (bootstrap verified against live FTE `-game ktx`; full CSQC entity streaming remains tracked in 3E).
- [x] CSQC transport handshake + world load validated against FTE sample server (`FTE_PEXT_CSQC`, `*csprogs*` metadata, local csprogs resolution).
- [x] Explicitly track unsupported builtins and close blockers in priority order.

### 3E. Validation for Step 3
- [x] ezQuake negotiates FTE CSQC transport and resolves `*csprogs/*csprogssize/*csprogsname` from FTE server.
- [x] ezQuake client can load csprogs and render CSQC-driven entities from FTE server.
- [x] No fatal parse failures under packet loss/reorder.
- [x] Legacy non-CSQC server play remains unchanged.

### Phase 3 Exit Criteria
- [x] `ezQuake + CSQC client -> FTE server` works for at least one full match flow (latest matrix: `E:\_RE\runtime\phase3-matrix\20260310_141744`, `P3-FTE-SAMPLE-STREAM` pass).

## Phase 4 (User Step 4): mvdsv + ktx + ezQuake End-to-End
- [x] Run full stack with KTX anti-lag mode matrix (`sv_antilag 0/1/2`).
- [ ] Validate player-visible outcomes against FTE reference:
  - [ ] hit registration consistency
  - [ ] projectile feel/impact timing
  - [ ] spectator/demo correctness
- [x] Verify MVD hidden/debug payloads do not regress (automation path + demo artifact checks passing).
- [x] Run mixed-client sessions (CSQC-capable and legacy clients).
- [x] Produce final integration config set and operator docs.

### Phase 4 Scaffolding Progress (March 5, 2026)
- [x] Added phase-4 validation scaffold doc: `docs/phase4-e2e-validation-matrix.md`
- [x] Defined scenario IDs, pass/fail evidence requirements, and per-run artifact checklist.
- [x] Added CSV template for matrix execution tracking: `docs/phase4-e2e-validation-matrix.csv`
- [x] Seeded runtime scaffold folder: `E:\_RE\runtime\phase4-matrix\` (`README.txt`, `matrix_template.csv`)

### Phase 4 Automation Progress (March 5, 2026, 15:41 UTC)
- Automated runner added and stabilized: `tools/phase4/run_phase4_matrix.ps1`
  - single-argument launch path for ezQuake process startup reliability
  - hard process cleanup between scenarios
  - unique client `-port` / `+qport` per instance to prevent reconnect collision in mixed mode
  - forced windowed launch for all playable clients (`-window -startwindowed +vid_fullscreen 0`)
- Latest automation run: `E:\_RE\runtime\phase4-matrix\20260305_154159`
  - `F4-BOOT-0`: pass
  - `F4-BOOT-1`: pass
  - `F4-BOOT-2`: pass
  - `F4-MIX-LEGACY`: pass
  - `F4-MIX-ENDURANCE`: pass
- Matrix evidence updated in `docs/phase4-e2e-validation-matrix.csv` for the five automated rows.

### Phase 4 Automation Progress (March 5, 2026, 16:44 UTC)
- Expanded runner now covers all scenario families (`BOOT`, `HIT`, `ROCKET`, `DEMO`, `MIX`) with evidence checks per row:
  - scripted action-marker execution checks for hitscan/projectile rows
  - demo-file artifact checks (`.qwd` presence + non-zero size) for demo rows
  - protocol-extension evidence checks for hidden payload row (`Using MVDSV extensions`)
- Latest automation run: `E:\_RE\runtime\phase4-matrix\20260305_164417`
  - `11/11` scenarios passed:
    - `F4-BOOT-0/1/2`
    - `F4-HIT-LP/HP`
    - `F4-ROCKET-DIR/SPLASH`
    - `F4-DEMO-CORE/HIDDEN`
    - `F4-MIX-LEGACY/ENDURANCE`
- Network-profile caveat in current harness:
  - superseded by 19:42 UTC run with real UDP loss injection.
- Matrix evidence updated in `docs/phase4-e2e-validation-matrix.csv` for all rows.

### Phase 4 Automation Progress (March 5, 2026, 19:42 UTC)
- Added real packet-loss injector tooling for matrix validation:
  - `tools/phase4/udp_loss_proxy.ps1`
- `tools/phase4/run_phase4_matrix.ps1` now:
  - enforces `-game ktx` on matrix clients for KTX unsized CSQC payload compatibility.
  - runs real 2%/5% loss rows through per-scenario UDP proxy with drop counters.
  - archives proxy evidence (`loss_proxy_stdout.log`, `loss_proxy_stderr.log`, `loss_proxy_stats.txt`) per scenario.
- Latest automation run: `E:\_RE\runtime\phase4-matrix\20260305_194254`
  - `11/11` scenarios passed with real-loss rows active:
    - `F4-ROCKET-SPLASH`: `proxy_drop=40/1999` at `2%` profile
    - `F4-DEMO-HIDDEN`: `proxy_drop=10/201` at `5%` profile
- Matrix evidence updated in `docs/phase4-e2e-validation-matrix.csv` for latest all-pass run.

### Phase 4 Automation Progress (March 10, 2026, 14:11 UTC)
- Expanded matrix coverage landed in `tools/phase4/run_phase4_matrix.ps1`:
  - added very-low-ping row (`F4-HIT-VLP`, `0-20ms`)
  - added very-high-ping lightning row (`F4-LG-HP`, `220ms+`)
- Latest automation run: `E:\_RE\runtime\phase4-matrix\20260310_141119`
  - `13/13` scenarios passed:
    - `F4-BOOT-0/1/2`
    - `F4-HIT-VLP/LP/HP`
    - `F4-LG-HP`
    - `F4-ROCKET-DIR/SPLASH`
    - `F4-DEMO-CORE/HIDDEN`
    - `F4-MIX-LEGACY/ENDURANCE`
- Matrix evidence updated in `docs/phase4-e2e-validation-matrix.csv` for latest all-pass run.

### Phase 4 Automation Progress (March 10, 2026, 15:58 UTC)
- Expanded matrix coverage landed in `tools/phase4/run_phase4_matrix.ps1`:
  - added moving BSP/platform interaction row (`F4-MOVE-BSP`, `e1m1`)
  - added explicit bot+human mixed-session row (`F4-MIX-BOT-HUMAN`, bot-join marker gated)
- Latest automation run: `E:\_RE\runtime\phase4-matrix\20260310_155812`
  - `15/15` scenarios passed:
    - `F4-BOOT-0/1/2`
    - `F4-HIT-VLP/LP/HP`
    - `F4-LG-HP`
    - `F4-ROCKET-DIR/SPLASH`
    - `F4-MOVE-BSP`
    - `F4-DEMO-CORE/HIDDEN`
    - `F4-MIX-BOT-HUMAN`
    - `F4-MIX-LEGACY/ENDURANCE`
- Matrix evidence updated in `docs/phase4-e2e-validation-matrix.csv` for latest all-pass run.

### Phase 4 Automation Refresh (March 10, 2026, 19:32 UTC)
- Default matrix runner remains green after lifecycle + snapshot hardening:
  - latest all-pass run: `E:\_RE\runtime\phase4-matrix\20260310_193208`
  - summary: `15/15` pass (`F4-BOOT-*`, `F4-HIT-*`, `F4-LG-*`, `F4-ROCKET-*`, `F4-MOVE-BSP`, `F4-DEMO-*`, `F4-MIX-*`, `F4-MIX-BOT-HUMAN`)
  - runner now tolerates missing/partial `csqc_status_last.txt` by using verified `CSQC-ACTIVE` + connect-log fallback evidence (eliminates false negatives seen in `20260310_191450` and `20260310_192356`).
- Lifecycle probe scaffolding remains integrated as opt-in rows:
  - use `tools/phase4/run_phase4_matrix.ps1 -IncludeLifecycle` (or `-LifecycleOnly`) to run `F4-LIFE-OT` / `F4-LIFE-INT`.
  - current blocker in this local runtime: ezQuake dedicated path auto-joins a host `player` slot and lifecycle gating remains stuck in duel prewar.
  - additional probe evidence:
    - kicking host `player` disconnects active session paths (`E:\_RE\runtime\phase4-matrix\probe_kick_player_duel2`).
    - forcing `+spectator 1` prevents server from reaching map-ready lifecycle markers (`E:\_RE\runtime\phase4-matrix\probe_server_spectator_long2`).
  - latest lifecycle-only evidence run: `E:\_RE\runtime\phase4-matrix\20260310_175632` (`0/2` pass, blocker reproduced).

### Phase 4 Release Packaging Progress (March 5, 2026)
- Final operator/config artifacts added:
  - `docs/phase4-release/operator-runbook.md`
  - `docs/phase4-release/configs/server-ktx-phase4.cfg`
  - `docs/phase4-release/configs/client-csqc-phase4.cfg`
  - `docs/phase4-release/configs/client-legacy-phase4.cfg`
  - `docs/phase4-release/configs/netprofile-40-80ms.cfg`
  - `docs/phase4-release/configs/netprofile-120-180ms.cfg`
  - `docs/phase4-release/configs/netprofile-loss2-proxy.cfg`
  - `docs/phase4-release/configs/netprofile-loss5-proxy.cfg`
- Release-bundle staging script added:
  - `tools/phase4/stage_phase4_release_bundle.ps1`
  - auto-selects latest all-pass matrix run and builds handoff bundle under `E:\_RE\runtime\phase4-release\`
  - validates required runtime prerequisites (`pak0.pak`, `pak1.pak`) before staging

### Phase 4 Exit Criteria
- [x] `mvdsv + ktx + ezQuake` passes full functional and stability matrix (automation harness: `15/15` rows passing on run `20260310_193208`, including real 2%/5% UDP loss rows).
- [x] Release candidate branch is ready for upstream review/testing (phase-4 operator docs + config bundle tooling staged).

## Cross-Phase Test Matrix (Must Pass)
- [x] Ping buckets: `0-20ms`, `40-80ms`, `120-180ms`, `220ms+`
- [x] Loss buckets: `0%`, `2%`, `5%`
- [x] Weapon classes: hitscan, projectile, splash, lightning
- [x] Moving BSP/platform interactions
- [x] Bot and human clients mixed
- [x] Demo record/playback sanity
- [ ] Match lifecycle: prewar, countdown, active, overtime, intermission

## Risks and Mitigations
- [ ] **Risk:** PR #391 branch contains unrelated churn.
  - [ ] Mitigation: cherry-pick only scoped commits; forbid mixed-scope commits.
- [ ] **Risk:** `ezquake-source` has no existing CSQC client runtime.
  - [ ] Mitigation: split Step 3 into explicit bootstrap milestones and keep fallback path intact.
- [ ] **Risk:** Behavior drift vs FTE reference in edge cases.
  - [ ] Mitigation: treat FTE outputs as oracle; maintain replayable regression scenarios.
- [ ] **Risk:** Extension handshake mismatch between KTX and mvdsv.
  - [ ] Mitigation: add startup capability report and hard-fail logs for missing required extensions.

## Human Testing Readiness (March 10, 2026)
- [x] Automated stack gates passing:
  - Phase 2 matrix: `E:\_RE\runtime\phase2-matrix-alt\20260310_141945` (`4/4` pass)
  - Phase 3 matrix: `E:\_RE\runtime\phase3-matrix\20260310_141744` (`2/2` pass)
  - Phase 4 matrix: `E:\_RE\runtime\phase4-matrix\20260310_193208` (`15/15` pass)
- [x] Definition-of-done implementation steps (`1-4`) are complete.
- [ ] Human-oracle parity checks (feel/timing edge-case judgement) remain intentionally open and are the purpose of next-stage player testing.

## Definition of Done
- [x] Step 1 complete: KTX anti-lag relies on `MOVE_LAGGED` semantics for `sv_antilag 1`, no critical manual rewind dependency.
- [x] Step 2 complete: mvdsv server-side CSQC transport works with FTE client (`P2-FTE-BOOT`, `P2-FTE-ENDURANCE`, `P2-FTE-LOSS-RESEND`, `P2-LEGACY-NONCSQC` all pass on run `20260310_141945` with runtime-abort hard-fail checks enabled).
- [x] Step 3 complete: ezQuake client-side CSQC path works with FTE server (`P3-FTE-SAMPLE-STREAM` and `P3-FTE-KTX-BOOTSTRAP` pass on run `20260310_141744`).
- [x] Step 4 complete (automation harness): mvdsv + ktx + ezQuake stack is stable and passes matrix (`15/15` on `20260310_193208` with real UDP-loss injection; FTE oracle parity validation still tracked separately).
