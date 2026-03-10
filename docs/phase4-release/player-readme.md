# Phase 4 Player Guide

## Purpose
Use this guide to join and test the packaged Phase 4 `ktx` stack as a player.
It covers both CSQC-capable clients and legacy (non-CSQC) clients.

## What You Can Test
- Anti-lag gameplay on `sv_antilag`.
- CSQC transport and payload updates (CSQC client path).
- Mixed sessions where CSQC and legacy clients play together.
- Demo/spectator stability during normal play.

## Client Types
- CSQC client:
  - Use `cl_csqc 1`.
  - Config: `configs/client-csqc-phase4.cfg`.
- Legacy client:
  - Use `cl_csqc 0`.
  - Config: `configs/client-legacy-phase4.cfg`.

## Required Runtime Rule
- Always start playable clients windowed:
  - `-window -startwindowed +vid_fullscreen 0`

## Quick Start
Run from the release bundle root.

### One-Click Launchers (Windows)
- CSQC client: `start_player_csqc.bat`
- Legacy client: `start_player_legacy.bat`

### CSQC Client (manual command)
```powershell
$basedir = (Resolve-Path .\runtime).Path
.\bin\ezquake.exe `
  -allowmultiple `
  -basedir "$basedir" `
  -game ktx `
  -port 28600 `
  -window -startwindowed -nosound +vid_fullscreen 0 `
  +name phase4_csqc_player `
  +clientport 28600 +qport 28700 `
  +exec configs/client-csqc-phase4.cfg `
  +connect 127.0.0.1:28500
```

### Legacy Client (manual command)
```powershell
$basedir = (Resolve-Path .\runtime).Path
.\bin\ezquake.exe `
  -allowmultiple `
  -basedir "$basedir" `
  -game ktx `
  -port 28601 `
  -window -startwindowed -nosound +vid_fullscreen 0 `
  +name phase4_legacy_player `
  +clientport 28601 +qport 28701 `
  +exec configs/client-legacy-phase4.cfg `
  +connect 127.0.0.1:28500
```

## Optional Network Profiles
- `exec configs/netprofile-40-80ms.cfg`
- `exec configs/netprofile-120-180ms.cfg`
- `exec configs/netprofile-loss2-proxy.cfg`
- `exec configs/netprofile-loss5-proxy.cfg`

Note: loss profiles assume host-side proxy setup. Without the proxy they only
change delay/jitter cvars.

## Player Test Checklist
- [ ] Connect to the server and confirm map/serverinfo loads.
- [ ] Confirm input and movement feel normal (no stuck states).
- [ ] Fire hitscan weapons and confirm expected hit feedback.
- [ ] Fire projectile weapons and confirm direct/splash registration.
- [ ] Verify lightning usage under high ping feels consistent.
- [ ] Record and stop a short demo, then playback locally.
- [ ] If using CSQC client: run `cl_csqc_status` and confirm:
  - [ ] `transport=enabled`
  - [ ] `world=yes`
  - [ ] entity/update counters increase while playing
- [ ] If using a mixed session (CSQC + legacy), verify both clients remain connected.

## Report Template
- Date/time:
- Client type: CSQC or legacy
- Net profile:
- Map/mode:
- What was expected:
- What happened:
- Repro steps:
- Attach logs/demo:
