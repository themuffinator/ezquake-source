#!/usr/bin/env python3
"""Build a cross-platform nightly testing kit bundle."""

from __future__ import annotations

import argparse
import datetime as dt
from pathlib import Path
import shutil
import subprocess
import sys
from typing import Iterable


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Create a nightly test kit bundle.")
    parser.add_argument("--platform", choices=("windows", "linux", "macos"), required=True)
    parser.add_argument("--repo-root", required=True, help="Repository root path.")
    parser.add_argument("--output-root", required=True, help="Output root for generated bundle.")
    parser.add_argument(
        "--binary-source",
        required=True,
        help="Binary payload source path (file or directory).",
    )
    parser.add_argument(
        "--launch-binary-relative",
        required=True,
        help="Relative binary path inside bundle used by launch scripts.",
    )
    parser.add_argument(
        "--runtime-base",
        default="",
        help="Optional runtime base directory to copy into bundle/runtime.",
    )
    parser.add_argument(
        "--bundle-name",
        default="",
        help="Optional explicit bundle directory name.",
    )
    parser.add_argument(
        "--archive-format",
        choices=("zip", "tar.gz"),
        default="zip",
        help="Archive format to generate next to bundle directory.",
    )
    return parser.parse_args()


def run_git_short_sha(repo_root: Path) -> str:
    try:
        value = subprocess.check_output(
            ["git", "-C", str(repo_root), "rev-parse", "--short", "HEAD"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
        return value or "unknown"
    except Exception:
        return "unknown"


def require_path(path: Path, label: str) -> None:
    if not path.exists():
        raise FileNotFoundError(f"{label} missing: {path}")


def copy_tree_contents(source_dir: Path, target_dir: Path) -> None:
    for entry in source_dir.iterdir():
        destination = target_dir / entry.name
        if entry.is_dir():
            shutil.copytree(entry, destination)
        else:
            shutil.copy2(entry, destination)


def copy_docs_and_configs(repo_root: Path, bundle_dir: Path) -> None:
    docs_phase4 = repo_root / "docs" / "phase4-release"
    configs_source = docs_phase4 / "configs"
    require_path(configs_source, "phase4 config folder")

    docs_required = [
        docs_phase4 / "operator-runbook.md",
        docs_phase4 / "player-readme.md",
        docs_phase4 / "serverhost-readme.md",
        repo_root / "docs" / "phase4-e2e-validation-matrix.md",
        repo_root / "docs" / "phase4-e2e-validation-matrix.csv",
        repo_root / "docs" / "ktx-pr391-move-lagged-csqc-implementation-plan.md",
    ]
    for file_path in docs_required:
        require_path(file_path, "documentation")

    docs_dir = bundle_dir / "docs"
    configs_dir = bundle_dir / "configs"
    docs_dir.mkdir(parents=True, exist_ok=True)
    shutil.copytree(configs_source, configs_dir, dirs_exist_ok=True)

    for doc_path in docs_required:
        shutil.copy2(doc_path, docs_dir / doc_path.name)

    shutil.copy2(docs_phase4 / "player-readme.md", bundle_dir / "README-player.md")
    shutil.copy2(docs_phase4 / "serverhost-readme.md", bundle_dir / "README-serverhost.md")
    shutil.copy2(docs_phase4 / "operator-runbook.md", bundle_dir / "README-operator.md")


def stage_binary_payload(binary_source: Path, bundle_dir: Path) -> None:
    require_path(binary_source, "binary payload")
    bin_dir = bundle_dir / "bin"
    bin_dir.mkdir(parents=True, exist_ok=True)
    if binary_source.is_dir():
        copy_tree_contents(binary_source, bin_dir)
    else:
        shutil.copy2(binary_source, bin_dir / binary_source.name)


def stage_tools(repo_root: Path, bundle_dir: Path) -> None:
    tool_source = repo_root / "tools" / "phase4" / "udp_loss_proxy.ps1"
    require_path(tool_source, "udp loss proxy tool")
    tools_dir = bundle_dir / "tools"
    tools_dir.mkdir(parents=True, exist_ok=True)
    shutil.copy2(tool_source, tools_dir / "udp_loss_proxy.ps1")


def write_runtime_template(bundle_dir: Path) -> None:
    runtime_template = bundle_dir / "runtime_template"
    (runtime_template / "id1").mkdir(parents=True, exist_ok=True)
    (runtime_template / "ktx").mkdir(parents=True, exist_ok=True)

    (runtime_template / "id1" / "README.txt").write_text(
        "Copy Quake pak files here:\n"
        "- pak0.pak\n"
        "- pak1.pak\n",
        encoding="ascii",
    )
    (runtime_template / "ktx" / "README.txt").write_text(
        "Copy KTX runtime assets here before starting host/client tests.\n"
        "Minimum expected payload:\n"
        "- csprogs.dat\n"
        "- qwprogs.qvm\n",
        encoding="ascii",
    )


def stage_runtime(bundle_dir: Path, runtime_base: str) -> str:
    if not runtime_base:
        write_runtime_template(bundle_dir)
        return "template"

    runtime_source = Path(runtime_base).resolve()
    require_path(runtime_source, "runtime base")
    runtime_target = bundle_dir / "runtime"
    runtime_target.mkdir(parents=True, exist_ok=True)
    copy_tree_contents(runtime_source, runtime_target)
    return "full"


def write_text(path: Path, lines: Iterable[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="ascii")


def write_windows_launchers(bundle_dir: Path, launch_binary_relative: str) -> None:
    binary_windows = launch_binary_relative.replace("/", "\\")
    bat_header = [
        "@echo off",
        "setlocal",
        "pushd \"%~dp0\"",
        "if exist \"%CD%\\runtime\" (",
        "  set \"BASEDIR=%CD%\\runtime\"",
        ") else (",
        "  set \"BASEDIR=%CD%\\runtime_template\"",
        ")",
        f"set \"EZQ_BIN=%CD%\\{binary_windows}\"",
        "if not exist \"%EZQ_BIN%\" (",
        "  echo Missing executable: %EZQ_BIN%",
        "  exit /b 1",
        ")",
    ]

    write_text(
        bundle_dir / "start_server.bat",
        bat_header
        + [
            "\"%EZQ_BIN%\" -dedicated -allowmultiple -basedir \"%BASEDIR%\" -game ktx -port 28500 +exec configs/server-ktx-phase4.cfg +map start",
            "popd",
            "endlocal",
        ],
    )

    write_text(
        bundle_dir / "start_player_csqc.bat",
        bat_header
        + [
            "\"%EZQ_BIN%\" -allowmultiple -basedir \"%BASEDIR%\" -game ktx -port 28600 -window -startwindowed -nosound +vid_fullscreen 0 +name nightly_csqc_player +clientport 28600 +qport 28700 +exec configs/client-csqc-phase4.cfg +connect 127.0.0.1:28500",
            "popd",
            "endlocal",
        ],
    )

    write_text(
        bundle_dir / "start_player_legacy.bat",
        bat_header
        + [
            "\"%EZQ_BIN%\" -allowmultiple -basedir \"%BASEDIR%\" -game ktx -port 28601 -window -startwindowed -nosound +vid_fullscreen 0 +name nightly_legacy_player +clientport 28601 +qport 28701 +exec configs/client-legacy-phase4.cfg +connect 127.0.0.1:28500",
            "popd",
            "endlocal",
        ],
    )

    write_text(
        bundle_dir / "launch_examples.ps1",
        [
            "# Launch examples for nightly test kit (Windows)",
            "if (Test-Path .\\runtime) {",
            "  $basedir = (Resolve-Path .\\runtime).Path",
            "} else {",
            "  $basedir = (Resolve-Path .\\runtime_template).Path",
            "}",
            "",
            f"$ezq = (Resolve-Path .\\{binary_windows}).Path",
            "",
            "# Dedicated host",
            "& $ezq -dedicated -allowmultiple -basedir \"$basedir\" -game ktx -port 28500 +exec configs/server-ktx-phase4.cfg +map start",
            "",
            "# CSQC player",
            "& $ezq -allowmultiple -basedir \"$basedir\" -game ktx -port 28600 -window -startwindowed -nosound +vid_fullscreen 0 +name nightly_csqc_player +clientport 28600 +qport 28700 +exec configs/client-csqc-phase4.cfg +connect 127.0.0.1:28500",
            "",
            "# Legacy player",
            "& $ezq -allowmultiple -basedir \"$basedir\" -game ktx -port 28601 -window -startwindowed -nosound +vid_fullscreen 0 +name nightly_legacy_player +clientport 28601 +qport 28701 +exec configs/client-legacy-phase4.cfg +connect 127.0.0.1:28500",
        ],
    )


def write_unix_launcher(bundle_dir: Path, filename: str, command: str) -> None:
    script_path = bundle_dir / filename
    write_text(
        script_path,
        [
            "#!/usr/bin/env bash",
            "set -euo pipefail",
            "ROOT=\"$(cd \"$(dirname \"${BASH_SOURCE[0]}\")\" && pwd)\"",
            "if [[ -d \"$ROOT/runtime\" ]]; then",
            "  BASEDIR=\"$ROOT/runtime\"",
            "else",
            "  BASEDIR=\"$ROOT/runtime_template\"",
            "fi",
            "EZQ_BIN=\"${EZQ_BIN:-$ROOT/" + command.split(" ")[0] + "}\"",
            "if [[ ! -e \"$EZQ_BIN\" ]]; then",
            "  echo \"Missing executable: $EZQ_BIN\" >&2",
            "  exit 1",
            "fi",
            "if [[ \"$EZQ_BIN\" == *.AppImage ]]; then",
            "  chmod +x \"$EZQ_BIN\" || true",
            "fi",
            "shift 0",
            "$EZQ_BIN " + " ".join(command.split(" ")[1:]),
        ],
    )
    mode = script_path.stat().st_mode
    script_path.chmod(mode | 0o111)


def write_unix_launchers(bundle_dir: Path, launch_binary_relative: str) -> None:
    shared_args = "-allowmultiple -basedir \"$BASEDIR\" -game ktx"
    write_unix_launcher(
        bundle_dir,
        "start_server.sh",
        f"{launch_binary_relative} -dedicated {shared_args} -port 28500 +exec configs/server-ktx-phase4.cfg +map start",
    )
    write_unix_launcher(
        bundle_dir,
        "start_player_csqc.sh",
        f"{launch_binary_relative} {shared_args} -port 28600 -window -startwindowed -nosound +vid_fullscreen 0 +name nightly_csqc_player +clientport 28600 +qport 28700 +exec configs/client-csqc-phase4.cfg +connect 127.0.0.1:28500",
    )
    write_unix_launcher(
        bundle_dir,
        "start_player_legacy.sh",
        f"{launch_binary_relative} {shared_args} -port 28601 -window -startwindowed -nosound +vid_fullscreen 0 +name nightly_legacy_player +clientport 28601 +qport 28701 +exec configs/client-legacy-phase4.cfg +connect 127.0.0.1:28500",
    )
    write_text(
        bundle_dir / "launch_examples.sh",
        [
            "#!/usr/bin/env bash",
            "set -euo pipefail",
            "ROOT=\"$(cd \"$(dirname \"${BASH_SOURCE[0]}\")\" && pwd)\"",
            "if [[ -d \"$ROOT/runtime\" ]]; then",
            "  BASEDIR=\"$ROOT/runtime\"",
            "else",
            "  BASEDIR=\"$ROOT/runtime_template\"",
            "fi",
            "EZQ_BIN=\"${EZQ_BIN:-$ROOT/" + launch_binary_relative + "}\"",
            "if [[ \"$EZQ_BIN\" == *.AppImage ]]; then",
            "  chmod +x \"$EZQ_BIN\" || true",
            "fi",
            "",
            "# Dedicated host",
            "\"$EZQ_BIN\" -dedicated -allowmultiple -basedir \"$BASEDIR\" -game ktx -port 28500 +exec configs/server-ktx-phase4.cfg +map start",
            "",
            "# CSQC player",
            "\"$EZQ_BIN\" -allowmultiple -basedir \"$BASEDIR\" -game ktx -port 28600 -window -startwindowed -nosound +vid_fullscreen 0 +name nightly_csqc_player +clientport 28600 +qport 28700 +exec configs/client-csqc-phase4.cfg +connect 127.0.0.1:28500",
            "",
            "# Legacy player",
            "\"$EZQ_BIN\" -allowmultiple -basedir \"$BASEDIR\" -game ktx -port 28601 -window -startwindowed -nosound +vid_fullscreen 0 +name nightly_legacy_player +clientport 28601 +qport 28701 +exec configs/client-legacy-phase4.cfg +connect 127.0.0.1:28500",
        ],
    )
    mode = (bundle_dir / "launch_examples.sh").stat().st_mode
    (bundle_dir / "launch_examples.sh").chmod(mode | 0o111)


def write_nightly_readme(bundle_dir: Path, platform: str, runtime_mode: str) -> None:
    platform_launcher = {
        "windows": "start_server.bat, start_player_csqc.bat, start_player_legacy.bat",
        "linux": "start_server.sh, start_player_csqc.sh, start_player_legacy.sh",
        "macos": "start_server.sh, start_player_csqc.sh, start_player_legacy.sh",
    }[platform]
    write_text(
        bundle_dir / "README-nightly.md",
        [
            "# ezQuake Nightly Testing Kit",
            "",
            "This bundle is generated from nightly build scripts and mirrors the Phase 4",
            "testing-kit layout with platform-specific binaries plus shared configs/docs.",
            "",
            "## Included",
            "- bin/ : nightly binary payload",
            "- configs/ : server/client/net profile templates",
            "- docs/ : operator/player/host and matrix references",
            "- tools/udp_loss_proxy.ps1 : host loss injection tool",
            "- README-player.md, README-serverhost.md, README-operator.md",
            "",
            "## Runtime payload",
            f"- mode: {runtime_mode}",
            "- if mode=template, fill runtime_template/id1 and runtime_template/ktx before tests",
            "",
            "## Launchers",
            f"- {platform_launcher}",
            "- launch examples: launch_examples.ps1 or launch_examples.sh",
            "",
            "## Notes",
            "- player clients should be started windowed",
            "- use +exec configs/*.cfg templates to keep test settings consistent",
        ],
    )


def write_manifest(
    bundle_dir: Path,
    platform: str,
    runtime_mode: str,
    binary_source: Path,
    launch_binary_relative: str,
    git_sha: str,
) -> None:
    bin_files = sum(1 for _ in (bundle_dir / "bin").rglob("*") if _.is_file())
    runtime_root = bundle_dir / "runtime"
    runtime_template_root = bundle_dir / "runtime_template"
    runtime_files = (
        sum(1 for _ in runtime_root.rglob("*") if _.is_file())
        if runtime_root.exists()
        else sum(1 for _ in runtime_template_root.rglob("*") if _.is_file())
    )
    write_text(
        bundle_dir / "manifest.txt",
        [
            f"bundle_dir={bundle_dir}",
            f"platform={platform}",
            f"generated_utc={dt.datetime.now(dt.timezone.utc).isoformat(timespec='seconds')}",
            f"git_sha={git_sha}",
            f"binary_source={binary_source}",
            f"launch_binary={launch_binary_relative}",
            f"runtime_mode={runtime_mode}",
            f"binary_files={bin_files}",
            f"runtime_files={runtime_files}",
            "tools=tools/udp_loss_proxy.ps1",
        ],
    )


def create_archive(bundle_dir: Path, archive_format: str) -> Path:
    base_name = str(bundle_dir)
    if archive_format == "zip":
        archive_path = Path(shutil.make_archive(base_name, "zip", bundle_dir))
    else:
        archive_path = Path(shutil.make_archive(base_name, "gztar", bundle_dir))
    return archive_path


def main() -> int:
    args = parse_args()
    repo_root = Path(args.repo_root).resolve()
    output_root = Path(args.output_root).resolve()
    binary_source = Path(args.binary_source).resolve()

    require_path(repo_root, "repository root")
    require_path(binary_source, "binary source")
    output_root.mkdir(parents=True, exist_ok=True)

    timestamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%d_%H%M%S")
    git_sha = run_git_short_sha(repo_root)
    bundle_name = args.bundle_name or f"nightly_{args.platform}_{timestamp}_{git_sha}"
    bundle_dir = output_root / bundle_name
    if bundle_dir.exists():
        raise FileExistsError(f"bundle directory already exists: {bundle_dir}")
    bundle_dir.mkdir(parents=True, exist_ok=True)

    copy_docs_and_configs(repo_root, bundle_dir)
    stage_binary_payload(binary_source, bundle_dir)
    stage_tools(repo_root, bundle_dir)
    runtime_mode = stage_runtime(bundle_dir, args.runtime_base)

    launch_binary_relative = args.launch_binary_relative.replace("\\", "/")
    launch_target = bundle_dir / Path(launch_binary_relative)
    require_path(launch_target, "launch binary path inside bundle")

    if args.platform == "windows":
        write_windows_launchers(bundle_dir, launch_binary_relative)
    else:
        write_unix_launchers(bundle_dir, launch_binary_relative)

    write_nightly_readme(bundle_dir, args.platform, runtime_mode)
    write_manifest(
        bundle_dir=bundle_dir,
        platform=args.platform,
        runtime_mode=runtime_mode,
        binary_source=binary_source,
        launch_binary_relative=launch_binary_relative,
        git_sha=git_sha,
    )

    archive_path = create_archive(bundle_dir, args.archive_format)

    print(f"bundle_dir={bundle_dir}")
    print(f"archive={archive_path}")
    print(f"platform={args.platform}")
    print(f"runtime_mode={runtime_mode}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
