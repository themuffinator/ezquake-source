param(
	[string]$RuntimeBase = "E:\_RE\runtime\phase3-interop\qwbase",
	[string]$OutputDir = "E:\_RE\runtime\phase2-interop-probe\legacy_probe1",
	[int]$Port = 28770,
	[int]$DurationSec = 30,
	[string]$MapName = "dm2"
)

$ErrorActionPreference = "Stop"

function Stop-IfRunning {
	param([System.Diagnostics.Process]$Process)
	if ($null -eq $Process) {
		return
	}
	$Process.Refresh()
	if (-not $Process.HasExited) {
		Stop-Process -Id $Process.Id -Force
		Start-Sleep -Milliseconds 500
	}
}

function Stop-AllTargets {
	Get-Process -Name "ezquake", "fteqw64" -ErrorAction SilentlyContinue | Stop-Process -Force
	Start-Sleep -Seconds 1
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$exePath = Join-Path $repoRoot "build-msvc-x64\Debug\ezquake.exe"
if (-not (Test-Path $exePath)) {
	throw "Missing executable: $exePath"
}

if (Test-Path $OutputDir) {
	Remove-Item -Recurse -Force $OutputDir
}
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$serverLog = Join-Path $OutputDir "server.log"
$clientLog = Join-Path $OutputDir "client.log"
$clientBase = Join-Path $OutputDir "legacy_client_base"
$clientCfg = Join-Path $clientBase "ezquake\phase2_legacy_auto.cfg"
New-Item -ItemType Directory -Force -Path $clientBase | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $clientBase "ezquake") | Out-Null

foreach ($d in @("id1", "ktx", "qw")) {
	$src = Join-Path $RuntimeBase $d
	if (Test-Path $src) {
		Copy-Item -Recurse -Force $src (Join-Path $clientBase $d)
	}
}

@(
	"echo P2_LEGACY_BOOT"
	"echo P2_LEGACY_CFG_LOADED"
) | Set-Content -Path $clientCfg -Encoding ascii

$server = $null
$client = $null

try {
	Stop-AllTargets

	$server = Start-Process -FilePath $exePath -WorkingDirectory $repoRoot -ArgumentList @(
		"-condebug", $serverLog,
		"-cheats",
		"-dedicated",
		"-allowmultiple",
		"-basedir", $RuntimeBase,
		"-game", "ktx",
		"-port", "$Port",
		"+developer", "1",
		"+sv_showdrop", "1",
		"+maxclients", "8",
		"+sv_progtype", "2",
		"+sv_csqc_progname", "csprogs.dat",
		"+sv_antilag", "1",
		"+map", $MapName
	) -PassThru
	Start-Sleep -Seconds 4

	$client = Start-Process -FilePath $exePath -WorkingDirectory $repoRoot -ArgumentList @(
		"-condebug", $clientLog,
		"-allowmultiple",
		"-window",
		"-startwindowed",
		"+vid_fullscreen", "0",
		"-nosound",
		"-basedir", $clientBase,
		"-game", "ktx",
		"+cl_csqc", "0",
		"+name", "phase2_legacy",
		"+connect", "127.0.0.1:$Port",
		"+echo", "P2_LEGACY_CONNECT_ISSUED",
		"+exec", "phase2_legacy_auto.cfg"
	) -PassThru

	Start-Sleep -Seconds $DurationSec
}
finally {
	Stop-IfRunning -Process $client
	Stop-IfRunning -Process $server
}

$summary = Join-Path $OutputDir "summary.txt"
$serverLines = @()
$clientLines = @()
if (Test-Path $serverLog) {
	$serverLines = @(Select-String -Path $serverLog -Pattern "player entered the game|CSQC-ACTIVE|csprogs|PEXT|extensions|legacy|dropped|timed out" -CaseSensitive:$false -ErrorAction SilentlyContinue | ForEach-Object { $_.Line })
}
if (Test-Path $clientLog) {
	$clientLines = @(Select-String -Path $clientLog -Pattern "P2_LEGACY_|svc_fte_csqcentities|bad server message|CL_ParseServerMessage|disconnect|connected|csqc|error|host_error" -CaseSensitive:$false -ErrorAction SilentlyContinue | ForEach-Object { $_.Line })
}

@(
	"output_dir=$OutputDir"
	"server_log=$serverLog"
	"client_log=$clientLog"
	"server_match_lines=$($serverLines.Count)"
	"client_match_lines=$($clientLines.Count)"
	"---server-lines---"
) + $serverLines + @(
	"---client-lines---"
) + $clientLines | Set-Content -Path $summary -Encoding ascii

Get-Content -Path $summary
