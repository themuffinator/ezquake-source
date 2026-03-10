param(
	[string]$MatrixRoot = "E:\_RE\runtime\phase4-matrix",
	[string]$OutputRoot = "E:\_RE\runtime\phase4-release",
	[string]$RuntimeBase = "E:\_RE\runtime\phase3-interop\qwbase",
	[string]$BuildOutput = "",
	[string]$MatrixRunId = ""
)

$ErrorActionPreference = "Stop"

function Resolve-MatrixRun {
	param(
		[string]$Root,
		[string]$RequestedRunId
	)

	if ($RequestedRunId) {
		$requested = Join-Path $Root $RequestedRunId
		if (-not (Test-Path (Join-Path $requested "matrix_results.csv"))) {
			throw "Requested matrix run not found or missing matrix_results.csv: $requested"
		}
		return $requested
	}

	$candidates = @(Get-ChildItem -Path $Root -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
	foreach ($candidate in $candidates) {
		$csvPath = Join-Path $candidate.FullName "matrix_results.csv"
		if (-not (Test-Path $csvPath)) {
			continue
		}

		$rows = @(Import-Csv $csvPath)
		if ($rows.Count -eq 0) {
			continue
		}

		$allPass = @($rows | Where-Object { $_.status -ne "pass" }).Count -eq 0
		if ($allPass) {
			return $candidate.FullName
		}
	}

	throw "No all-pass matrix run found under $Root"
}

function Assert-Path {
	param(
		[string]$PathToCheck,
		[string]$Label
	)

	if (-not (Test-Path $PathToCheck)) {
		throw "$Label missing: $PathToCheck"
	}
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$matrixRun = Resolve-MatrixRun -Root $MatrixRoot -RequestedRunId $MatrixRunId
$resolvedBuildOutput = $BuildOutput
if (-not $resolvedBuildOutput) {
	$resolvedBuildOutput = Join-Path $repoRoot "build-msvc-x64\Debug"
}
$runId = Split-Path -Leaf $matrixRun
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$bundleDir = Join-Path $OutputRoot ("{0}_phase4_rc_{1}" -f $timestamp, $runId)

Assert-Path -PathToCheck (Join-Path $repoRoot "docs\phase4-release\operator-runbook.md") -Label "operator runbook"
Assert-Path -PathToCheck (Join-Path $repoRoot "docs\phase4-release\player-readme.md") -Label "player readme"
Assert-Path -PathToCheck (Join-Path $repoRoot "docs\phase4-release\serverhost-readme.md") -Label "serverhost readme"
Assert-Path -PathToCheck (Join-Path $repoRoot "docs\phase4-release\configs\server-ktx-phase4.cfg") -Label "server config"
Assert-Path -PathToCheck (Join-Path $repoRoot "tools\phase4\udp_loss_proxy.ps1") -Label "udp loss proxy tool"
Assert-Path -PathToCheck (Join-Path $resolvedBuildOutput "ezquake.exe") -Label "ezQuake executable"
Assert-Path -PathToCheck (Join-Path $RuntimeBase "id1\pak0.pak") -Label "runtime id1 pak0"
Assert-Path -PathToCheck (Join-Path $RuntimeBase "id1\pak1.pak") -Label "runtime id1 pak1"
Assert-Path -PathToCheck (Join-Path $RuntimeBase "ktx\csprogs.dat") -Label "runtime ktx csprogs"
Assert-Path -PathToCheck (Join-Path $RuntimeBase "ktx\qwprogs.qvm") -Label "runtime ktx qwprogs"

New-Item -ItemType Directory -Force -Path $bundleDir | Out-Null
$bundleDocs = Join-Path $bundleDir "docs"
$bundleConfigs = Join-Path $bundleDir "configs"
$bundleEvidence = Join-Path $bundleDir "evidence"
$bundleBin = Join-Path $bundleDir "bin"
$bundleRuntime = Join-Path $bundleDir "runtime"
$bundleTools = Join-Path $bundleDir "tools"
New-Item -ItemType Directory -Force -Path $bundleDocs | Out-Null
New-Item -ItemType Directory -Force -Path $bundleConfigs | Out-Null
New-Item -ItemType Directory -Force -Path $bundleEvidence | Out-Null
New-Item -ItemType Directory -Force -Path $bundleBin | Out-Null
New-Item -ItemType Directory -Force -Path $bundleRuntime | Out-Null
New-Item -ItemType Directory -Force -Path $bundleTools | Out-Null

# Copy release docs/config templates.
Copy-Item -Force (Join-Path $repoRoot "docs\phase4-release\operator-runbook.md") (Join-Path $bundleDocs "operator-runbook.md")
Copy-Item -Force (Join-Path $repoRoot "docs\phase4-release\player-readme.md") (Join-Path $bundleDocs "player-readme.md")
Copy-Item -Force (Join-Path $repoRoot "docs\phase4-release\serverhost-readme.md") (Join-Path $bundleDocs "serverhost-readme.md")
Copy-Item -Recurse -Force (Join-Path $repoRoot "docs\phase4-release\configs\*") $bundleConfigs
Copy-Item -Force (Join-Path $repoRoot "docs\phase4-e2e-validation-matrix.md") (Join-Path $bundleDocs "phase4-e2e-validation-matrix.md")
Copy-Item -Force (Join-Path $repoRoot "docs\phase4-e2e-validation-matrix.csv") (Join-Path $bundleDocs "phase4-e2e-validation-matrix.csv")
Copy-Item -Force (Join-Path $repoRoot "docs\ktx-pr391-move-lagged-csqc-implementation-plan.md") (Join-Path $bundleDocs "ktx-pr391-move-lagged-csqc-implementation-plan.md")
Copy-Item -Force (Join-Path $repoRoot "docs\phase4-release\player-readme.md") (Join-Path $bundleDir "README-player.md")
Copy-Item -Force (Join-Path $repoRoot "docs\phase4-release\serverhost-readme.md") (Join-Path $bundleDir "README-serverhost.md")
Copy-Item -Force (Join-Path $repoRoot "tools\phase4\udp_loss_proxy.ps1") (Join-Path $bundleTools "udp_loss_proxy.ps1")

# Copy binaries and runtime payload for standalone host/player testing.
Copy-Item -Recurse -Force (Join-Path $resolvedBuildOutput "*") $bundleBin
Copy-Item -Recurse -Force (Join-Path $RuntimeBase "*") $bundleRuntime

# Copy matrix evidence summary.
Copy-Item -Force (Join-Path $matrixRun "summary.txt") (Join-Path $bundleEvidence "summary.txt")
Copy-Item -Force (Join-Path $matrixRun "matrix_results.csv") (Join-Path $bundleEvidence "matrix_results.csv")
Set-Content -Path (Join-Path $bundleEvidence "source-run-path.txt") -Encoding ascii -Value $matrixRun

$launchExamples = @'
# Launch examples for phase4 release bundle
# Run from the bundle root.

$basedir = (Resolve-Path .\runtime).Path

# 1) Server
.\bin\ezquake.exe -dedicated -allowmultiple -basedir "$basedir" -game ktx -port 28500 +exec configs/server-ktx-phase4.cfg +map start

# 2) CSQC client
.\bin\ezquake.exe -allowmultiple -basedir "$basedir" -game ktx -port 28600 -window -startwindowed -nosound +vid_fullscreen 0 +name phase4_csqc +clientport 28600 +qport 28700 +exec configs/client-csqc-phase4.cfg +connect 127.0.0.1:28500

# 3) Legacy client
.\bin\ezquake.exe -allowmultiple -basedir "$basedir" -game ktx -port 28601 -window -startwindowed -nosound +vid_fullscreen 0 +name phase4_legacy +clientport 28601 +qport 28701 +exec configs/client-legacy-phase4.cfg +connect 127.0.0.1:28500
'@
Set-Content -Path (Join-Path $bundleDir "launch_examples.ps1") -Encoding ascii -Value $launchExamples

$startServerBat = @'
@echo off
setlocal
pushd "%~dp0"
set "BASEDIR=%CD%\runtime"
.\bin\ezquake.exe -dedicated -allowmultiple -basedir "%BASEDIR%" -game ktx -port 28500 +exec configs/server-ktx-phase4.cfg +map start
popd
endlocal
'@
Set-Content -Path (Join-Path $bundleDir "start_server.bat") -Encoding ascii -Value $startServerBat

$startPlayerCsqcBat = @'
@echo off
setlocal
pushd "%~dp0"
set "BASEDIR=%CD%\runtime"
.\bin\ezquake.exe -allowmultiple -basedir "%BASEDIR%" -game ktx -port 28600 -window -startwindowed -nosound +vid_fullscreen 0 +name phase4_csqc_player +clientport 28600 +qport 28700 +exec configs/client-csqc-phase4.cfg +connect 127.0.0.1:28500
popd
endlocal
'@
Set-Content -Path (Join-Path $bundleDir "start_player_csqc.bat") -Encoding ascii -Value $startPlayerCsqcBat

$startPlayerLegacyBat = @'
@echo off
setlocal
pushd "%~dp0"
set "BASEDIR=%CD%\runtime"
.\bin\ezquake.exe -allowmultiple -basedir "%BASEDIR%" -game ktx -port 28601 -window -startwindowed -nosound +vid_fullscreen 0 +name phase4_legacy_player +clientport 28601 +qport 28701 +exec configs/client-legacy-phase4.cfg +connect 127.0.0.1:28500
popd
endlocal
'@
Set-Content -Path (Join-Path $bundleDir "start_player_legacy.bat") -Encoding ascii -Value $startPlayerLegacyBat

$rows = @(Import-Csv (Join-Path $matrixRun "matrix_results.csv"))
$passes = @($rows | Where-Object { $_.status -eq "pass" }).Count
$fails = @($rows | Where-Object { $_.status -ne "pass" }).Count
$binaryFiles = @(Get-ChildItem -File -Recurse $bundleBin)
$runtimeFiles = @(Get-ChildItem -File -Recurse $bundleRuntime)

$manifest = @(
	"bundle_dir=$bundleDir"
	"matrix_run=$matrixRun"
	"matrix_rows=$($rows.Count)"
	"passes=$passes"
	"fails=$fails"
	"runtime_base=$RuntimeBase"
	"build_output=$resolvedBuildOutput"
	"binary_files=$($binaryFiles.Count)"
	"runtime_files=$($runtimeFiles.Count)"
	"tools=tools/udp_loss_proxy.ps1"
	"launchers=start_server.bat,start_player_csqc.bat,start_player_legacy.bat"
	"notes=loss profiles validated with real UDP drop proxy (bundle: tools/udp_loss_proxy.ps1)"
)
Set-Content -Path (Join-Path $bundleDir "manifest.txt") -Encoding ascii -Value $manifest

Get-Content (Join-Path $bundleDir "manifest.txt")
