param(
	[string]$ConfigurePreset = "msbuild-x64",
	[string]$BuildPreset = "msbuild-x64-release",
	[string]$BuildConfiguration = "Release",
	[string]$OutputRoot = "",
	[string]$RuntimeBase = "",
	[switch]$SkipBootstrap,
	[switch]$SkipBuild
)

$ErrorActionPreference = "Stop"

function Resolve-PythonCommand {
	$pythonExe = ""
	$pythonPrefixArgs = @()

	$candidate = Get-Command python -ErrorAction SilentlyContinue
	if ($candidate) {
		$pythonExe = "python"
	}
	else {
		$candidate = Get-Command py -ErrorAction SilentlyContinue
		if ($candidate) {
			$pythonExe = "py"
			$pythonPrefixArgs = @("-3")
		}
	}

	if (-not $pythonExe) {
		throw "Python runtime not found (python/py)."
	}

	return [PSCustomObject]@{
		exe = $pythonExe
		args = $pythonPrefixArgs
	}
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
if (-not $OutputRoot) {
	$OutputRoot = Join-Path $repoRoot "artifacts\nightly"
}

if (-not $SkipBootstrap) {
	& (Join-Path $repoRoot "bootstrap.ps1")
}

if (-not $SkipBuild) {
	cmake --preset $ConfigurePreset
	cmake --build --preset $BuildPreset
}

$buildDir = Join-Path $repoRoot ("build-{0}\{1}" -f $ConfigurePreset, $BuildConfiguration)
Assert-Path -PathToCheck (Join-Path $buildDir "ezquake.exe") -Label "ezQuake binary"

$pythonCmd = Resolve-PythonCommand
$packagerScript = Join-Path $repoRoot "tools\nightly\package_test_kit.py"
$arguments = @(
	$packagerScript,
	"--platform", "windows",
	"--repo-root", $repoRoot,
	"--output-root", $OutputRoot,
	"--binary-source", $buildDir,
	"--launch-binary-relative", "bin/ezquake.exe"
)
if ($RuntimeBase) {
	$arguments += @("--runtime-base", $RuntimeBase)
}

& $pythonCmd.exe @($pythonCmd.args) @arguments
