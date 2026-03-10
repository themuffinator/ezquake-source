param(
	[string]$RuntimeBase = "E:\_RE\runtime\phase3-interop\qwbase",
	[string]$OutputRoot = "E:\_RE\runtime\phase2-matrix",
	[int]$BasePort = 29256
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$probeFte = Join-Path $PSScriptRoot "probe_phase2_fte_interop.ps1"
$probeLegacy = Join-Path $PSScriptRoot "probe_phase2_legacy_client.ps1"
if (-not (Test-Path $probeFte)) {
	throw "Missing script: $probeFte"
}
if (-not (Test-Path $probeLegacy)) {
	throw "Missing script: $probeLegacy"
}

$runId = Get-Date -Format "yyyyMMdd_HHmmss"
$runDir = Join-Path $OutputRoot $runId
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

$results = @()

function Add-Result {
	param(
		[string]$ScenarioId,
		[string]$Status,
		[string]$Evidence,
		[string]$Notes
	)

	$script:results += [PSCustomObject]@{
		scenario_id = $ScenarioId
		status = $Status
		evidence = $Evidence
		notes = $Notes
	}
}

function Bool-ToLabel {
	param([bool]$Value)
	if ($Value) {
		return "yes"
	}
	return "no"
}

function Read-FirstMatchLine {
	param(
		[string]$Path,
		[string]$Pattern
	)

	if (-not (Test-Path $Path)) {
		return ""
	}

	$m = Select-String -Path $Path -Pattern $Pattern -CaseSensitive:$false | Select-Object -First 1
	if ($m) {
		return $m.Line
	}
	return ""
}

function Read-UIntFromFile {
	param(
		[string]$Path,
		[string]$Field
	)

	if (-not (Test-Path $Path)) {
		return 0
	}

	$m = Select-String -Path $Path -Pattern ("^{0}=(\d+)$" -f [regex]::Escape($Field)) | Select-Object -First 1
	if ($m) {
		$rx = [regex]::Match($m.Line, "$Field=(\d+)")
		if ($rx.Success) {
			return [int]$rx.Groups[1].Value
		}
	}
	return 0
}

function Read-FieldValueFromFile {
	param(
		[string]$Path,
		[string]$Field
	)

	if (-not (Test-Path $Path)) {
		return ""
	}

	$m = Select-String -Path $Path -Pattern ("^{0}=(.*)$" -f [regex]::Escape($Field)) | Select-Object -First 1
	if ($m) {
		$rx = [regex]::Match($m.Line, "^[^=]+=(.*)$")
		if ($rx.Success) {
			return $rx.Groups[1].Value
		}
	}

	return ""
}

function Describe-ProbeFailure {
	param(
		[string]$ScenarioDir,
		[int]$ProbeExit
	)

	$summaryPath = Join-Path $ScenarioDir "summary.txt"
	$connected = Read-UIntFromFile -Path $summaryPath -Field "fte_connected"
	$loadFailed = Read-UIntFromFile -Path $summaryPath -Field "fte_csqc_load_failed"
	$runtimeFailed = Read-UIntFromFile -Path $summaryPath -Field "fte_csqc_runtime_failed"
	$runtimeAbortHits = Read-UIntFromFile -Path $summaryPath -Field "fte_csqc_runtime_abort_hits"
	$loadFailureHits = Read-UIntFromFile -Path $summaryPath -Field "fte_csqc_failure_hits"
	$hostEndgameHits = Read-UIntFromFile -Path $summaryPath -Field "fte_host_endgame_hits"
	$connectTarget = Read-FieldValueFromFile -Path $summaryPath -Field "connect_target"

	if ($runtimeFailed -gt 0) {
		return "probe_exit=$ProbeExit (CSQC runtime abort; runtime_abort_hits=$runtimeAbortHits; target=$connectTarget)"
	}

	if ($loadFailed -gt 0) {
		return "probe_exit=$ProbeExit (CSQC load failure; failure_hits=$loadFailureHits; host_endgame_hits=$hostEndgameHits; target=$connectTarget)"
	}

	if ($connected -eq 0) {
		return "probe_exit=$ProbeExit (FTE did not reach connected state; target=$connectTarget)"
	}

	return "probe_exit=$ProbeExit (probe failure; target=$connectTarget)"
}

function Extract-UInt {
	param(
		[string]$Line,
		[string]$Field
	)

	$m = [regex]::Match($Line, "$Field=(\d+)")
	if ($m.Success) {
		return [int]$m.Groups[1].Value
	}
	return 0
}

$port = $BasePort

# Scenario 1: FTE handshake + csprogs + initial CSQC stream
$s1Dir = Join-Path $runDir "P2-FTE-BOOT"
& powershell -NoProfile -ExecutionPolicy Bypass -File $probeFte `
	-RuntimeBase $RuntimeBase `
	-OutputDir $s1Dir `
	-Port $port `
	-DurationSec 30 `
	-MapName "dm2" | Out-Null
$s1ProbeExit = $LASTEXITCODE

if ($s1ProbeExit -ne 0) {
	$s1FailNote = Describe-ProbeFailure -ScenarioDir $s1Dir -ProbeExit $s1ProbeExit
	Add-Result -ScenarioId "P2-FTE-BOOT" -Status "fail" -Evidence $s1Dir -Notes $s1FailNote
	$port++
}
else {
	$s1ServerLog = Join-Path $s1Dir "server.log"
	$s1Csqc = Read-FirstMatchLine -Path $s1ServerLog -Pattern "CSQC-ACTIVE"
	$s1HasCsprogs = (Read-FirstMatchLine -Path $s1ServerLog -Pattern "\*csprogs") -ne ""
	$s1HasPext = (Read-FirstMatchLine -Path $s1ServerLog -Pattern "Using FTE extensions") -ne ""
	$s1Updates = Extract-UInt -Line $s1Csqc -Field "updates"
	$s1Proj = Extract-UInt -Line $s1Csqc -Field "type_projectile"
	$s1Status = if ($s1HasCsprogs -and $s1HasPext -and $s1Updates -gt 0) { "pass" } else { "fail" }
	$s1Notes = "csprogs=" + (Bool-ToLabel -Value $s1HasCsprogs) + "; pext=" + (Bool-ToLabel -Value $s1HasPext) + "; updates=$s1Updates; projectile=$s1Proj"
	Add-Result -ScenarioId "P2-FTE-BOOT" -Status $s1Status -Evidence $s1Dir -Notes $s1Notes
	$port++
}

# Scenario 2: FTE endurance session (transport stability)
$s2Dir = Join-Path $runDir "P2-FTE-ENDURANCE"
& powershell -NoProfile -ExecutionPolicy Bypass -File $probeFte `
	-RuntimeBase $RuntimeBase `
	-OutputDir $s2Dir `
	-Port $port `
	-DurationSec 120 `
	-MapName "dm2" | Out-Null
$s2ProbeExit = $LASTEXITCODE

if ($s2ProbeExit -ne 0) {
	$s2FailNote = Describe-ProbeFailure -ScenarioDir $s2Dir -ProbeExit $s2ProbeExit
	Add-Result -ScenarioId "P2-FTE-ENDURANCE" -Status "fail" -Evidence $s2Dir -Notes $s2FailNote
	$port++
}
else {
	$s2ServerLog = Join-Path $s2Dir "server.log"
	$s2FteLog = Join-Path $s2Dir "fte_base\fte\qconsole.log"
	$s2Csqc = Read-FirstMatchLine -Path $s2ServerLog -Pattern "CSQC-ACTIVE"
	$s2Updates = Extract-UInt -Line $s2Csqc -Field "updates"
	$s2FatalServer = (Read-FirstMatchLine -Path $s2ServerLog -Pattern "SV_Error|Host_Error|Fatal|crash") -ne ""
	$s2FatalFte = (Read-FirstMatchLine -Path $s2FteLog -Pattern "Host_Error|Fatal|segfault|crash") -ne ""
	$s2Status = if ($s2Updates -gt 0 -and -not $s2FatalServer -and -not $s2FatalFte) { "pass" } else { "fail" }
	$s2Notes = "updates=$s2Updates; fatal_server=" + (Bool-ToLabel -Value $s2FatalServer) + "; fatal_fte=" + (Bool-ToLabel -Value $s2FatalFte)
	Add-Result -ScenarioId "P2-FTE-ENDURANCE" -Status $s2Status -Evidence $s2Dir -Notes $s2Notes
	$port++
}

# Scenario 3: Deterministic loss/resend proof (driver routed through loss proxy)
$s3Dir = Join-Path $runDir "P2-FTE-LOSS-RESEND"
& powershell -NoProfile -ExecutionPolicy Bypass -File $probeFte `
	-RuntimeBase $RuntimeBase `
	-OutputDir $s3Dir `
	-Port $port `
	-DurationSec 60 `
	-MapName "dm2" `
	-ForceMatchStart `
	-SpawnDriverClient `
	-RouteDriverThroughLossProxy `
	-LossPercent 5 | Out-Null
$s3ProbeExit = $LASTEXITCODE

if ($s3ProbeExit -ne 0) {
	$s3FailNote = Describe-ProbeFailure -ScenarioDir $s3Dir -ProbeExit $s3ProbeExit
	Add-Result -ScenarioId "P2-FTE-LOSS-RESEND" -Status "fail" -Evidence $s3Dir -Notes $s3FailNote
	$port++
}
else {
	$s3ServerLog = Join-Path $s3Dir "server.log"
	$s3Summary = Join-Path $s3Dir "summary.txt"
	$s3ProxyStats = Join-Path $s3Dir "loss_proxy_stats.txt"
	$s3Csqc = Read-FirstMatchLine -Path $s3ServerLog -Pattern "CSQC-ACTIVE"
	$s3Updates = Extract-UInt -Line $s3Csqc -Field "updates"
	$s3ProjectileLines = @(Select-String -Path $s3ServerLog -Pattern "CSQC-PROJECTILE" -ErrorAction SilentlyContinue).Count
	$s3ProxyIn = Read-UIntFromFile -Path $s3ProxyStats -Field "total_in"
	$s3ProxyDrop = Read-UIntFromFile -Path $s3ProxyStats -Field "total_drop"
	$s3FteConnected = Read-UIntFromFile -Path $s3Summary -Field "fte_connected"
	$s3FteLoadFailed = Read-UIntFromFile -Path $s3Summary -Field "fte_csqc_load_failed"
	$s3FteRuntimeFailed = Read-UIntFromFile -Path $s3Summary -Field "fte_csqc_runtime_failed"
	$s3FteNotConnectedHits = Read-UIntFromFile -Path $s3Summary -Field "fte_not_connected_hits"
	$s3Timeout = ($s3FteConnected -eq 0) -or ($s3FteNotConnectedHits -gt 0)
	$s3FatalServer = (Read-FirstMatchLine -Path $s3ServerLog -Pattern "SV_Error|Host_Error|Fatal|crash") -ne ""
	$s3Status = if ($s3ProxyIn -gt 0 -and $s3ProxyDrop -gt 0 -and $s3Updates -gt 0 -and -not $s3Timeout -and -not $s3FatalServer -and $s3FteLoadFailed -eq 0 -and $s3FteRuntimeFailed -eq 0) { "pass" } else { "fail" }
	$s3Notes = "proxy_in=$s3ProxyIn; proxy_drop=$s3ProxyDrop; updates=$s3Updates; projectile_lines=$s3ProjectileLines; timeout=" + (Bool-ToLabel -Value $s3Timeout) + "; fte_load_failed=" + (Bool-ToLabel -Value ($s3FteLoadFailed -ne 0)) + "; fte_runtime_failed=" + (Bool-ToLabel -Value ($s3FteRuntimeFailed -ne 0)) + "; fatal_server=" + (Bool-ToLabel -Value $s3FatalServer)
	Add-Result -ScenarioId "P2-FTE-LOSS-RESEND" -Status $s3Status -Evidence $s3Dir -Notes $s3Notes
	$port++
}

# Scenario 4: Non-CSQC client regression check
$s4Dir = Join-Path $runDir "P2-LEGACY-NONCSQC"
& powershell -NoProfile -ExecutionPolicy Bypass -File $probeLegacy `
	-RuntimeBase $RuntimeBase `
	-OutputDir $s4Dir `
	-Port $port `
	-DurationSec 30 `
	-MapName "dm2" | Out-Null

$s4ServerLog = Join-Path $s4Dir "server.log"
$legacyLine = Read-FirstMatchLine -Path $s4ServerLog -Pattern "Client supports 0x2148f008 fte extensions"
$legacyJoined = (Read-FirstMatchLine -Path $s4ServerLog -Pattern "phase2_legacy entered the game") -ne ""
$legacyStatus = if ($legacyLine -and $legacyJoined) { "pass" } else { "fail" }
$legacyNotes = "legacy_ext_without_csqc=" + (Bool-ToLabel -Value ([bool]$legacyLine)) + "; joined=" + (Bool-ToLabel -Value $legacyJoined)
Add-Result -ScenarioId "P2-LEGACY-NONCSQC" -Status $legacyStatus -Evidence $s4Dir -Notes $legacyNotes
$port++

$csvPath = Join-Path $runDir "phase2_validation_matrix.csv"
$results | Export-Csv -Path $csvPath -NoTypeInformation -Encoding ascii

$summaryPath = Join-Path $runDir "summary.txt"
@(
	"run_id=$runId"
	"run_dir=$runDir"
	"matrix=$csvPath"
) + ($results | ForEach-Object {
	"$($_.scenario_id): status=$($_.status) notes=$($_.notes)"
}) | Set-Content -Path $summaryPath -Encoding ascii

Get-Content -Path $summaryPath

if (@($results | Where-Object { $_.status -ne "pass" }).Count -gt 0) {
	exit 1
}
