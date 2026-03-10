# Phase 3 FTE Server Validation Matrix

## Scope
- Validates Step 3 (`ezQuake + CSQC client -> FTE server`) with reproducible probes.
- Confirms:
  - FTE sample server CSQC stream can be consumed without fatal parser errors.
  - KTX-on-FTE bootstrap path remains stable in default userinfo-only mode.

## Automation
- Runner: `tools/phase3/run_phase3_validation_matrix.ps1`
- Probes:
  - `tools/phase3/probe_phase3_fte_server.ps1`
  - `tools/phase3/probe_phase3_fte_ktx_server.ps1`
- Repro command:
  - `powershell -NoProfile -ExecutionPolicy Bypass -File tools/phase3/run_phase3_validation_matrix.ps1 -DurationSeconds 50`

## Latest Run
- Run directory: `E:\_RE\runtime\phase3-matrix\20260310_141744`
- CSV snapshot: `docs/phase3-fte-server-validation-matrix.csv`
- Result: `2/2` passing
  - `P3-FTE-SAMPLE-STREAM`: pass
  - `P3-FTE-KTX-BOOTSTRAP`: pass

## Caveats
- KTX-on-FTE full CSQC entity streaming is still absent on this local FTE pairing unless `enablecsqc` is forced, and the forced path remains unstable (disconnect-loop/server-exit behavior).
- This matrix treats KTX-on-FTE bootstrap stability as the gate for that pairing, while Step-3 “full CSQC flow” is satisfied by the FTE sample server stream scenario.
