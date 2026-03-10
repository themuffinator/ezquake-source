# Phase 2 FTE Client Validation Matrix

## Scope
- Validates Step 2 (`mvdsv + ktx CSQC server -> FTE client`) using reproducible local probes.
- Confirms:
  - FTE extension negotiation and `*csprogs*` handshake.
  - server-side CSQC `SendEntity` transport activity.
  - non-CSQC legacy client compatibility.

## Automation
- Runner: `tools/phase2/run_phase2_validation_matrix.ps1`
- Runtime prep: `tools/phase2/prepare_phase2_csqc_runtime.ps1`
- Probes:
  - `tools/phase2/probe_phase2_fte_interop.ps1`
  - `tools/phase2/probe_phase2_legacy_client.ps1`
- Repro sequence:
  - `powershell -NoProfile -ExecutionPolicy Bypass -File tools/phase2/prepare_phase2_csqc_runtime.ps1 -BuildFromKtxQc`
  - `powershell -NoProfile -ExecutionPolicy Bypass -File tools/phase2/run_phase2_validation_matrix.ps1 -RuntimeBase E:\_RE\runtime\phase2-csqc-runtime-alt -OutputRoot E:\_RE\runtime\phase2-matrix-alt`
- Latest run:
  - `E:\_RE\runtime\phase2-matrix-alt\20260310_141945`
  - CSV snapshot: `docs/phase2-fte-client-validation-matrix.csv`

## Evidence Signals
- Handshake:
  - `Using FTE extensions ...`
  - `*csprogs`, `*csprogssize`, `*csprogsname` in `fullserverinfo`
- CSQC stream activity:
  - `CSQC-ACTIVE: ... updates=...`
- Legacy non-CSQC path:
  - extension mask without CSQC bit (`0x2148f008`) for `phase2_legacy`

## Caveats
- The runtime `ktx/csprogs.dat` must match the active KTX CSQC schema. A mismatched runtime csprogs can connect but still abort at CSQC runtime (`CSQC_Abort`).
- `prepare_phase2_csqc_runtime.ps1` exists to make this deterministic (copy baseline runtime + install known-good `csprogs.dat` + create `csprogsvers/<checksum>.dat` alias).
- Loss/latency validation is covered by `P2-FTE-LOSS-RESEND` in the latest matrix run (`proxy_drop=136/2624`, `projectile_lines=1`).
