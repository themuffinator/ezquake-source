# Phase 4 Release Artifacts

This folder contains operator and player handoff material for the validated
`mvdsv + ktx + ezQuake` Phase 4 stack.

## Audience Guides
- Player guide: `docs/phase4-release/player-readme.md`
- Server host guide: `docs/phase4-release/serverhost-readme.md`
- Operator runbook: `docs/phase4-release/operator-runbook.md`

## Config Templates
- `docs/phase4-release/configs/server-ktx-phase4.cfg`
- `docs/phase4-release/configs/client-csqc-phase4.cfg`
- `docs/phase4-release/configs/client-legacy-phase4.cfg`
- `docs/phase4-release/configs/netprofile-40-80ms.cfg`
- `docs/phase4-release/configs/netprofile-120-180ms.cfg`
- `docs/phase4-release/configs/netprofile-loss2-proxy.cfg`
- `docs/phase4-release/configs/netprofile-loss5-proxy.cfg`

## Tooling
- Real-loss proxy tool: `tools/phase4/udp_loss_proxy.ps1`
- Release bundle staging script: `tools/phase4/stage_phase4_release_bundle.ps1`

## Release Bundle Contents
Staged bundle output now includes a standalone Windows test package with:
- `bin/` (all build output binaries from `build-msvc-x64/Debug`)
- `runtime/` (copied from `E:\_RE\runtime\phase3-interop\qwbase`, including `id1` and `ktx`)
- `configs/` (server/client/net profile templates)
- `docs/` plus top-level `README-player.md` and `README-serverhost.md`
- `evidence/` (matrix summary and csv from the selected all-pass run)

## Current Baseline
- Latest all-pass matrix run: `E:\_RE\runtime\phase4-matrix\20260310_193208`
- Result: `15/15` pass
