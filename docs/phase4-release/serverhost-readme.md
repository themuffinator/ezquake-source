# Phase 4 Server Host Guide

## Purpose
Use this guide to host and validate the packaged Phase 4 `ktx` stack with
`mvdsv + ezQuake` transport and mixed client support.

## Validated Feature Set
- KTX gameplay module via `sv_progtype 2` and `sv_csqc_progname csprogs.dat`.
- CSQC transport on the server path (`CSQC-ACTIVE` entity updates).
- Anti-lag matrix coverage across ping/loss buckets.
- Mixed-session support (CSQC + legacy clients).
- Demo/spectator path stability.

Latest all-pass evidence run:
- `E:\_RE\runtime\phase4-matrix\20260310_193208` (`15/15` pass)

## Prerequisites
- Release bundle includes:
  - `bin/ezquake.exe`
  - `runtime/id1/pak0.pak`
  - `runtime/id1/pak1.pak`
  - `runtime/ktx/csprogs.dat`
  - `runtime/ktx/qwprogs.qvm`
  - `configs/server-ktx-phase4.cfg`

## Core Server Config
Base config:
- `configs/server-ktx-phase4.cfg`

Important settings in that template:
- `sv_progtype 2`
- `sv_csqc_progname csprogs.dat`
- `sv_antilag 1`
- `maxclients 8`
- `deathmatch 3`

## Server Launch
Run from the release bundle root.

### One-Click Launcher (Windows)
- `start_server.bat`

```powershell
$basedir = (Resolve-Path .\runtime).Path
.\bin\ezquake.exe `
  -dedicated -allowmultiple `
  -basedir "$basedir" `
  -game ktx -port 28500 `
  +exec configs/server-ktx-phase4.cfg `
  +map start
```

## Host Setup Checklist
- [ ] Server starts and map loads without fatal errors.
- [ ] KTX banner appears in log output.
- [ ] `CSQC-ACTIVE` lines appear when CSQC client connects.
- [ ] `*csprogs` metadata is visible in client/server info exchange.
- [ ] Mixed client session (CSQC + legacy) connects successfully.
- [ ] Demo/spectator path works for at least one short session.

## Host Validation Checklist
- [ ] Launch host using `start_server.bat` or the manual command above.
- [ ] Connect one CSQC client and one legacy client.
- [ ] Confirm both clients stay connected during map changes.
- [ ] Validate anti-lag behavior with hitscan and projectile weapons.
- [ ] Validate demo recording/playback from at least one client.
- [ ] Save repro notes and logs for any issue.

## Loss/Latency Testing
- For host-side loss simulation, use:
  - `tools/udp_loss_proxy.ps1`
- Apply player-side net profiles:
  - `exec configs/netprofile-loss2-proxy.cfg`
  - `exec configs/netprofile-loss5-proxy.cfg`

## Known Local Limitation
- Lifecycle probe rows (`F4-LIFE-OT`, `F4-LIFE-INT`) remain opt-in and blocked in
 this local runtime due host-player/duel-mode constraints.
- This does not block the current 15-scenario baseline gate.
