# Phase 4 Operator Runbook

## Scope
- Stack: `mvdsv + ktx + ezQuake` on branch `antilag`.
- Validation baseline: `E:\_RE\runtime\phase4-matrix\20260310_193208` (`15/15` pass).

## Runtime Rule
- Always run playable clients windowed.
- Required flags: `-window -startwindowed +vid_fullscreen 0`

## Prerequisites
- ezQuake debug build exists:
  - `E:\Repositories\ezquake-source\build-msvc-x64\Debug\ezquake.exe`
- Runtime basedir exists with Quake assets:
  - `E:\_RE\runtime\phase3-interop\qwbase\id1\pak0.pak`
  - `E:\_RE\runtime\phase3-interop\qwbase\id1\pak1.pak`
- KTX game assets are staged under:
  - `E:\_RE\runtime\phase3-interop\qwbase\ktx`

## Config Set
- Server base config: `docs/phase4-release/configs/server-ktx-phase4.cfg`
- CSQC client base config: `docs/phase4-release/configs/client-csqc-phase4.cfg`
- Legacy client base config: `docs/phase4-release/configs/client-legacy-phase4.cfg`
- Player guide: `docs/phase4-release/player-readme.md`
- Server host guide: `docs/phase4-release/serverhost-readme.md`
- Optional network profiles:
  - `docs/phase4-release/configs/netprofile-40-80ms.cfg`
  - `docs/phase4-release/configs/netprofile-120-180ms.cfg`
  - `docs/phase4-release/configs/netprofile-loss2-proxy.cfg`
  - `docs/phase4-release/configs/netprofile-loss5-proxy.cfg`

## Launch Commands
Run from `E:\Repositories\ezquake-source`.

### 1. Dedicated server
```powershell
.\build-msvc-x64\Debug\ezquake.exe `
  -dedicated -allowmultiple `
  -basedir E:\_RE\runtime\phase3-interop\qwbase `
  -game ktx -port 28500 `
  +exec docs/phase4-release/configs/server-ktx-phase4.cfg `
  +map start
```

### 2. CSQC client
```powershell
.\build-msvc-x64\Debug\ezquake.exe `
  -allowmultiple `
  -basedir E:\_RE\runtime\phase3-interop\qwbase `
  -game ktx `
  -port 28600 `
  -window -startwindowed -nosound +vid_fullscreen 0 `
  +name phase4_csqc `
  +clientport 28600 +qport 28700 `
  +exec docs/phase4-release/configs/client-csqc-phase4.cfg `
  +connect 127.0.0.1:28500
```

### 3. Legacy client (optional mixed session)
```powershell
.\build-msvc-x64\Debug\ezquake.exe `
  -allowmultiple `
  -basedir E:\_RE\runtime\phase3-interop\qwbase `
  -game ktx `
  -port 28601 `
  -window -startwindowed -nosound +vid_fullscreen 0 `
  +name phase4_legacy `
  +clientport 28601 +qport 28701 `
  +exec docs/phase4-release/configs/client-legacy-phase4.cfg `
  +connect 127.0.0.1:28500
```

## Automated Validation
- Run:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/phase4/run_phase4_matrix.ps1
```
- Expected output:
  - `total_scenarios=15`
  - `failed=0`
- Latest known good run:
  - `E:\_RE\runtime\phase4-matrix\20260310_193208`

## Release Bundle Staging
- Run:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/phase4/stage_phase4_release_bundle.ps1
```
- Output root:
  - `E:\_RE\runtime\phase4-release\<timestamp>\`

## Loss Injection
- Matrix loss rows (`2%` and `5%`) use a real UDP drop proxy:
  - `tools/phase4/udp_loss_proxy.ps1`
- The runner starts/stops the proxy automatically and records evidence in each scenario folder:
  - `loss_proxy_stdout.log`
  - `loss_proxy_stderr.log`
  - `loss_proxy_stats.txt`
