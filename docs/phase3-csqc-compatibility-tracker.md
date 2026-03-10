# Phase 3 CSQC Compatibility Tracker

## Scope
- Repo: `E:\Repositories\ezquake-source`
- Branch: `antilag`
- Goal: track ezQuake CSQC client compatibility status for:
  - FTE sample CSQC server/mod baseline.
  - KTX CSQC payloads (`PROJECTILE`, `WEAPONINFO`, `WEAPONDEF`).

## Runtime Status Command
- Console command: `cl_csqc_status`
- Purpose:
  - print transport/csprogs state.
  - print parse/drop counters.
  - print capability map and current blocker list.

## Capability Map
- `read.byte/short`: supported.
- `read.coord/angle/float`: supported.
- `render.projectile`: supported.
- `render.viewmodel`: supported.
- `input.frame`: supported.
- `event.cgamepacket.sized`: supported.
- `event.cgamepacket.unsized`: unsupported (dropped safely).
- `vm.bytecode_execution`: unsupported.
- `draw.scripts_and_hud`: unsupported.

## Priority Blockers
- `P1`: Add CSQC VM loader/executor for csprogs bytecode.
- `P1`: Implement CSQC draw/event builtins used by FTE sample mods.
- `P2`: Add robust decode bridge for unsized `cgamepacket` payload variants.
- `P2`: Improve KTX-on-FTE streaming parity beyond bootstrap-stable mode.

## Phase 3 Validation Notes
- CSQC parser now treats malformed CSQC payloads as recoverable:
  - drops current message instead of escalating to fatal parser error.
  - drops unknown unsized CSQC entity payloads safely.
  - keeps legacy non-CSQC path unchanged when no CSQC transport is active.
- FTE handshake compatibility fix now in place:
  - connect packet advertises `csqcactive` and `*csqcactive` when `FTE_PEXT_CSQC` is negotiated.
  - client sends `enablecsqc` / `disablecsqc` server control commands during CSQC lifecycle sync.
- Replacement-delta compatibility path now implemented:
  - client negotiates `FTE_PEXT2_REPLACEMENTDELTAS` (now observed as `fte2=0xa` against FTE sample server).
  - `svc_fte_updateentities` parse path is active and stable in probe runs.
  - replacement entity-index coding is handled for CSQC entity headers.
  - non-`ktx` unsized CSQC entity payloads for FTE sample classes are decoded via a dedicated bridge path; unknown/unsupported unsized payloads are still dropped safely to avoid parser desync.
- Local verification snapshot (March 5, 2026):
  - `cmake --build --preset msvc-x64-debug` passed.
  - `build-msvc-x64/Debug/ezquake.exe -dedicated +map dm2 +quit` passed.

## Latest Interop Probe (March 5, 2026, 14:56 UTC)
- Runtime artifacts:
  - `E:\_RE\runtime\phase3-interop\reports\phase3_run_20260305_145634.txt`
  - `E:\_RE\runtime\phase3-interop\reports\csqc_status_last_20260305_145634.txt`
  - `E:\_RE\runtime\phase3-interop\reports\phase3_net_sample_20260305_145634.txt`
- Observed handshake state:
  - `reason=world-loaded`
  - `cls_state=3`
  - `transport=enabled`, `pext=yes`, `world=yes`
  - `csprogs name=csprogs.dat`, local file detected (`local=yes`)
- Environment correction required for this result:
  - `-basedir` must point to runtime base with valid Quake `id1` assets (`pak0.pak` + `pak1.pak`).
  - custom map-only paks are insufficient for client bootstrap (`gfx/palette.lmp` failure).
- Remaining limitation:
  - parse counters are still `0`; full CSQC VM execution/draw path remains unimplemented.

## Latest Interop Probe (March 5, 2026, 18:44 UTC)
- Probe runner:
  - `tools/phase3/probe_phase3_fte_server.ps1`
- Runtime artifacts:
  - `E:\_RE\runtime\phase3-interop\reports\phase3_fte_server_probe_20260305_184414.txt`
  - `E:\_RE\runtime\phase3-interop\reports\phase3_fte_qconsole_20260305_184414.log`
  - `E:\_RE\runtime\phase3-interop\reports\phase3_fte_status_20260305_184414.txt`
- Observed state:
  - `welcome_seen=True`
  - `enable_sent_seen=True`
  - server text confirms activation: `Welcome to csqctest!`
  - CSQC snapshot still reports no FTE CSQC opcodes (`csqcentities/sized/cgamepacket` all `0`) in current scripted idle-map flow.
- Interpretation:
  - handshake/activation path is now accepted by FTE sample server.
  - remaining gap is live CSQC opcode flow coverage and payload parity (still pending full Step 3 exit).

## Latest Interop Probe (March 5, 2026, 19:13 UTC)
- Probe runner:
  - `tools/phase3/probe_phase3_fte_server.ps1`
- Runtime artifacts:
  - `E:\_RE\runtime\phase3-interop\reports\phase3_fte_server_probe_20260305_191332.txt`
  - `E:\_RE\runtime\phase3-interop\reports\phase3_fte_qconsole_20260305_191332.log`
  - `E:\_RE\runtime\phase3-interop\reports\phase3_fte_status_20260305_191332.txt`
- Observed state:
  - `welcome_seen=True`
  - `enable_sent_seen=True`
  - negotiated extension2 now includes replacement deltas (`Using FTE extensions2 0xa`).
  - live opcode stream observed: `shownet updateentities=98`, `shownet csqcentities=98`, snapshot histogram `76=97 86=97`.
  - no parser aborts during probe duration.
- Interpretation:
  - previous opcode-flow blocker is resolved: FTE server is now streaming CSQC transport traffic to ezQuake.
  - remaining Step-3 gap is payload/VM parity (FTE sample unsized CSQC payloads are intentionally dropped outside `ktx` gamedir).

## Latest Interop Probe (March 5, 2026, 21:04 UTC)
- Probe runner:
  - `tools/phase3/probe_phase3_fte_ktx_server.ps1`
- Runtime artifacts:
  - `E:\_RE\runtime\phase3-interop\reports\phase3_fte_ktx_probe_20260305_210444.txt`
  - `E:\_RE\runtime\phase3-interop\reports\phase3_fte_ktx_qconsole_20260305_210444.log`
  - `E:\_RE\runtime\phase3-interop\reports\phase3_fte_ktx_status_20260305_210444.txt`
- Observed state:
  - `milestone2_bootstrap_pass=True`
  - `enable_sent_seen=True`
  - serverinfo confirms KTX package path: `*gamedir\ktx`, `ktxver\1.47-dev`, `*csprogs\0xd6a0b4ab`.
  - snapshot confirms CSQC bootstrap with local KTX package resolution: `transport=enabled`, `pext=yes`, `csprogs name=csprogs.dat local=yes`.
  - `streaming_pass=False`: no `svc_fte_csqcentities`/`svc_fte_updateentities` observed in this KTX-on-FTE run; qconsole shows post-signon disconnect loop after `stufftext: skins`.
- Interpretation:
  - Phase-3 second compatibility milestone (run KTX CSQC package against FTE server) is met at bootstrap/activation level.
  - remaining Step-3 blocker is stable live CSQC entity streaming/render flow under this server pairing.

## Latest Interop Probe (March 10, 2026, 11:13 UTC)
- Probe runner:
  - `tools/phase3/probe_phase3_fte_server.ps1`
- Runtime artifacts:
  - `E:\_RE\runtime\phase3-interop\reports\phase3_fte_server_probe_20260310_111352.txt`
  - `E:\_RE\runtime\phase3-interop\reports\phase3_fte_qconsole_20260310_111352.log`
  - `E:\_RE\runtime\phase3-interop\reports\phase3_fte_status_20260310_111352.txt`
- Observed state:
  - live opcode stream present (`shownet updateentities=1326`, `shownet csqcentities=1325`).
  - default non-`ktx` guard dropped unsized CSQC payloads (`drops total=1265`, `updates=0`).
- Interpretation:
  - transport flow is healthy; payload compatibility is still constrained by the non-`ktx` unsized decode guard.

## Latest Interop Probe (March 10, 2026, 11:21 UTC)
- Probe runner:
  - `tools/phase3/probe_phase3_fte_server.ps1` (now setting `cl_csqc_allow_unsized_nonktx 1` in probe config)
- Runtime artifacts:
  - `E:\_RE\runtime\phase3-interop\reports\phase3_fte_server_probe_20260310_112110.txt`
  - `E:\_RE\runtime\phase3-interop\reports\phase3_fte_qconsole_20260310_112110.log`
  - `E:\_RE\runtime\phase3-interop\reports\phase3_fte_status_20260310_112110.txt`
- Observed state:
  - parser now accepts non-`ktx` unsized stream in probe flow (`entity_packets=2`, `updates=1`, `drops total=1`).
  - no fatal parser aborts during probe duration.
- Interpretation:
  - unsized decode bridge is partially validated for FTE sample probe path when explicitly enabled.

## Latest Interop Probe (March 10, 2026, 11:19 UTC)
- Probe runner:
  - `tools/phase3/probe_phase3_fte_ktx_server.ps1`
- Runtime artifacts:
  - `E:\_RE\runtime\phase3-interop\reports\phase3_fte_ktx_probe_20260310_111939.txt`
  - `E:\_RE\runtime\phase3-interop\reports\phase3_fte_ktx_qconsole_20260310_111939.log`
  - `E:\_RE\runtime\phase3-interop\reports\phase3_fte_ktx_status_20260310_111939.txt`
- Observed state:
  - bootstrap remains stable in userinfo-only mode (`milestone2_bootstrap_pass=True`, `disconnect_loop_hits=0`).
  - streaming still absent (`messages_csqcentities=0`, `parse_updates=0`).
- Interpretation:
  - bootstrap path is stable; live KTX-on-FTE CSQC entity streaming remains the primary Step-3 blocker.

## Forced Enable Diagnostic (March 10, 2026, 11:16 UTC)
- Runtime artifacts:
  - `E:\_RE\runtime\phase3-interop\reports\phase3_fte_ktx_probe_20260310_111645.txt`
  - `E:\_RE\runtime\phase3-interop\reports\phase3_fte_ktx_qconsole_20260310_111645.log`
- Observed state:
  - forcing `enablecsqc` (via `cl_csqc_force_enablecmd_ktx 1`) reproduces disconnect-loop behavior (`Connection lost or aborted` flood, `server_exited_early=True`).
- Interpretation:
  - explicit enable command remains unsafe for this local FTE `-game ktx` pairing; keep userinfo-only default path.

## Decoder Fix + Validation Matrix (March 10, 2026, 14:17 UTC)
- Code-path update:
  - `src/cl_csqc.c` now has a dedicated non-`ktx` unsized decode path for FTE sample entity classes (`rocket`, `nail`, `player`, `gib`, `explosion`) to avoid KTX-type ID collisions on unsized streams.
  - this removed the recurring `projectile angles block` drops and `svc_bad` parser aborts seen when FTE sample class IDs overlapped KTX type constants.
- New matrix runner:
  - `tools/phase3/run_phase3_validation_matrix.ps1`
  - latest all-pass run: `E:\_RE\runtime\phase3-matrix\20260310_141744`
  - rows:
    - `P3-FTE-SAMPLE-STREAM`: pass (`report_pass=True`, `fatal_hits=0`, `disconnect_loops=0`)
    - `P3-FTE-KTX-BOOTSTRAP`: pass (`milestone2_bootstrap_pass=True`, `session_stable=True`, `fatal_hits=0`)
- Interpretation:
  - Step-3 transport/decode stability against FTE sample server is now automation-verified.
  - KTX-on-FTE remains bootstrap-stable in default mode; forced `enablecsqc` on this local FTE pairing remains a known unstable diagnostic path.
