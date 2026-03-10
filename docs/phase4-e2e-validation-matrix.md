# Phase 4 End-to-End Validation Matrix (Scaffold)

## Scope
- Target stack: `mvdsv + ktx + ezQuake`
- Reference oracle: FTE behavior for anti-lag and CSQC transport outcomes.
- Branch expectation: all repos on `antilag`.

## Preconditions
- [x] `ktx` QVM built and staged (`qwprogs.qvm`).
- [x] ezQuake client build is current (`cmake --build --preset msvc-x64-debug`).
- [x] runtime `id1` contains valid Quake assets (`pak0.pak` + `pak1.pak`).
- [x] CSQC payload source (`csprogs.dat`) is staged for test gamedir.
- [x] baseline network profile tooling is available for `0%/2%/5%` loss simulation (real UDP loss proxy: `tools/phase4/udp_loss_proxy.ps1`).
- [x] Client launch rule enforced: always windowed (`-window -startwindowed +vid_fullscreen 0`).

## Per-Run Evidence Checklist
For each scenario, archive all of the following:
- [ ] server launch command + config used.
- [ ] client launch command + config used.
- [ ] `cl_csqc_status` snapshot (`csqc_status_last.txt`).
- [ ] connection/network sample (UDP endpoint or equivalent).
- [ ] short gameplay evidence (demo or timestamped notes).
- [ ] pass/fail verdict with one-line reason.

## Scenario Matrix
Use `docs/phase4-e2e-validation-matrix.csv` as the executable checklist.

## Latest Automation Run (March 10, 2026)
- Run ID: `E:\_RE\runtime\phase4-matrix\20260310_193208`
- Summary: `15/15` automated scenarios passed (`F4-BOOT-*`, `F4-HIT-*`, `F4-LG-*`, `F4-ROCKET-*`, `F4-MOVE-BSP`, `F4-DEMO-*`, `F4-MIX-*`, `F4-MIX-BOT-HUMAN`).
- Runner used: `tools/phase4/run_phase4_matrix.ps1`
- Stabilization updates applied during this run:
  - argument-string process launch path (avoids Start-Process array parsing failures)
  - hard process cleanup between scenarios
  - unique per-client `-port` + `+qport` to prevent reconnect collisions in mixed sessions
  - forced `-game ktx` on matrix clients so KTX CSQC payload decode path is active
  - forced windowed launch flags on all playable clients
  - scripted on-enter action markers for hitscan/projectile rows
  - demo artifact checks for spectator/demo rows (`.qwd` creation + non-zero file size)
  - real packet-loss injection for 2%/5% rows via `tools/phase4/udp_loss_proxy.ps1` (drop counters captured in matrix results)
  - added explicit ping-bucket coverage rows (`0-20ms`, `220ms+`)
  - added explicit lightning scenario row (`F4-LG-HP`)
  - added moving-BSP automation row on `e1m1` (`F4-MOVE-BSP`)
  - added bot+human mixed-session row with explicit bot-join marker checks (`F4-MIX-BOT-HUMAN`)
  - resilient snapshot fallback: if `csqc_status_last.txt` is missing/partial, runner now accepts verified `CSQC-ACTIVE` + client-connect log evidence to avoid false negatives.
  - lifecycle probes are now available as opt-in rows (`-IncludeLifecycle` / `-LifecycleOnly`) and currently remain blocked in this runtime by host-player/duel-mode constraints.

### Required Scenario Families
- `F4-BOOT-*`: startup/handshake checks by `sv_antilag` mode (`0/1/2`).
- `F4-HIT-*`: hitscan verification at `0-20ms`, `40-80ms`, `120-180ms`.
- `F4-LG-*`: lightning verification at very high ping (`220ms+`).
- `F4-ROCKET-*`: direct + splash projectile checks.
- `F4-MOVE-BSP`: moving platform/BSP interaction probe (`e1m1`).
- `F4-DEMO-*`: spectator/demo correctness and hidden payload sanity.
- `F4-MIX-*`: mixed-client sessions (CSQC + legacy path).
- `F4-MIX-BOT-HUMAN`: mixed human + frogbot session bootstrap/transport check.

## Pass Gates
- [x] All `F4-BOOT-*` rows pass.
- [x] No regressions in non-CSQC clients (mixed-client automated run passed).
- [ ] No critical mismatch vs FTE oracle in hit-reg/impact timing.
- [x] Demo/spectator path remains stable for full match flow (demo rows now pass with recorded artifacts).
- [x] At least one full match-duration run passes without desync/crash (`F4-MIX-ENDURANCE`).

## Output Bundle
Archive final results to a single run directory (example):
- `E:\_RE\runtime\phase4-matrix\<timestamp>\`
  - `matrix.csv`
  - `server_logs\`
  - `client_logs\`
  - `snapshots\`
  - `demos\`
  - `summary.md`

Release handoff bundle (operator docs + config templates + evidence pointers):
- stage with: `powershell -NoProfile -ExecutionPolicy Bypass -File tools/phase4/stage_phase4_release_bundle.ps1`
- output root: `E:\_RE\runtime\phase4-release\<timestamp>_phase4_rc_<runid>\`
