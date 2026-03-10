# Nightly Build And Testing Kit

## Purpose
Nightly scripts build ezQuake on each supported platform and package a test kit
with a consistent layout for host/player validation.

## Included In Every Kit
- `bin/` nightly binary payload for the target platform
- `configs/` Phase 4 host/player/netprofile configs
- `docs/` Phase 4 runbook and validation references
- `tools/udp_loss_proxy.ps1` loss simulation helper
- launchers:
  - Windows: `start_server.bat`, `start_player_csqc.bat`, `start_player_legacy.bat`
  - Linux/macOS: `start_server.sh`, `start_player_csqc.sh`, `start_player_legacy.sh`
- `manifest.txt` and `README-nightly.md`

## Runtime Modes
- Full runtime mode:
  - pass `--runtime-base <path>` to copy an existing runtime into `runtime/`.
- Template mode:
  - if `--runtime-base` is omitted, bundle contains `runtime_template/` with
    instructions for `id1` and `ktx` assets.

## Local Script Entry Points
- Windows:
  - `powershell -NoProfile -ExecutionPolicy Bypass -File tools/nightly/build_nightly_windows.ps1`
- Linux:
  - `bash tools/nightly/build_nightly_linux.sh`
- macOS:
  - `bash tools/nightly/build_nightly_macos.sh`

Default output root:
- `artifacts/nightly/`

## Useful Parameters
- Windows script:
  - `-OutputRoot <path>`
  - `-RuntimeBase <path>`
  - `-BuildConfiguration Release|Debug|RelWithDebInfo`
  - `-SkipBootstrap`
  - `-SkipBuild`
- Linux script:
  - `--output-root <path>`
  - `--runtime-base <path>`
  - `--skip-build`
  - `--binary-source <path>`
- macOS script:
  - `--output-root <path>`
  - `--runtime-base <path>`
  - `--skip-bootstrap`
  - `--skip-build`
  - `--binary-source <path>`

## CI Workflow
- Workflow file: `.github/workflows/nightly-kit.yml`
- Triggers:
  - nightly schedule (`02:15 UTC`)
  - `workflow_dispatch`
- Artifact names:
  - `nightly-kit-windows`
  - `nightly-kit-linux`
  - `nightly-kit-macos`
