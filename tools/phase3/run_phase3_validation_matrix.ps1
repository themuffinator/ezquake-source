param(
	[string]$RuntimeBase = "E:\_RE\runtime\phase3-interop\qwbase",
	[string]$OutputRoot = "E:\_RE\runtime\phase3-matrix",
	[int]$DurationSeconds = 70
)

$ErrorActionPreference = "Stop"

$probeSample = Join-Path $PSScriptRoot "probe_phase3_fte_server.ps1"
$probeKtx = Join-Path $PSScriptRoot "probe_phase3_fte_ktx_server.ps1"
if (-not (Test-Path $probeSample)) {
	throw "Missing script: $probeSample"
}
if (-not (Test-Path $probeKtx)) {
	throw "Missing script: $probeKtx"
}

function Extract-ReportPathFromOutput {
	param([string[]]$OutputLines)

	foreach ($line in $OutputLines) {
		if ($line -match '^report_path=(.+)$') {
			return $Matches[1].Trim()
		}
	}

	return ""
}

function Read-FieldValue {
	param(
		[string]$Path,
		[string]$Field
	)

	if (-not (Test-Path $Path)) {
		return ""
	}

	$m = Select-String -Path $Path -Pattern ("^{0}=(.*)$" -f [regex]::Escape($Field)) | Select-Object -First 1
	if ($m) {
		return ([regex]::Match($m.Line, "^[^=]+=(.*)$")).Groups[1].Value.Trim()
	}

	return ""
}

function Read-BoolField {
	param(
		[string]$Path,
		[string]$Field
	)

	$v = Read-FieldValue -Path $Path -Field $Field
	if ([string]::IsNullOrWhiteSpace($v)) {
		return $false
	}
	return $v -ieq "true" -or $v -eq "1"
}

function Read-IntField {
	param(
		[string]$Path,
		[string]$Field
	)

	$v = Read-FieldValue -Path $Path -Field $Field
	if ([string]::IsNullOrWhiteSpace($v)) {
		return 0
	}
	return [int]$v
}

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

function Fallback-String {
	param(
		[string]$Value,
		[string]$Fallback = "<missing>"
	)

	if ([string]::IsNullOrWhiteSpace($Value)) {
		return $Fallback
	}

	return $Value
}

$runId = Get-Date -Format "yyyyMMdd_HHmmss"
$runDir = Join-Path $OutputRoot $runId
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

$results = @()

# Scenario 1: FTE sample CSQC stream on ezQuake
$s1Output = & powershell -NoProfile -ExecutionPolicy Bypass -File $probeSample -DurationSeconds $DurationSeconds
$s1Exit = $LASTEXITCODE
$s1Report = Extract-ReportPathFromOutput -OutputLines $s1Output
$s1Pass = $false
if ($s1Exit -eq 0 -and $s1Report -and (Test-Path $s1Report)) {
	$s1Pass = Read-BoolField -Path $s1Report -Field "report_pass"
}
$s1Status = if ($s1Pass) { "pass" } else { "fail" }
$s1FatalHits = Read-IntField -Path $s1Report -Field "fatal_hits"
$s1Disconnects = Read-IntField -Path $s1Report -Field "disconnect_loop_hits"
$s1Notes = "exit=$s1Exit; report=$(Fallback-String -Value $s1Report); report_pass=$s1Pass; fatal_hits=$s1FatalHits; disconnect_loops=$s1Disconnects"
Add-Result -ScenarioId "P3-FTE-SAMPLE-STREAM" -Status $s1Status -Evidence (Fallback-String -Value $s1Report -Fallback $runDir) -Notes $s1Notes

# Scenario 2: KTX package bootstrap on FTE server (userinfo-only stable path)
$s2Output = & powershell -NoProfile -ExecutionPolicy Bypass -File $probeKtx -DurationSeconds $DurationSeconds -RuntimeBase $RuntimeBase
$s2Exit = $LASTEXITCODE
$s2Report = Extract-ReportPathFromOutput -OutputLines $s2Output
$s2Bootstrap = Read-BoolField -Path $s2Report -Field "milestone2_bootstrap_pass"
$s2Stable = Read-BoolField -Path $s2Report -Field "session_stable"
$s2FatalHits = Read-IntField -Path $s2Report -Field "fatal_hits"
$s2Pass = ($s2Exit -eq 0) -and $s2Bootstrap -and $s2Stable -and ($s2FatalHits -eq 0)
$s2Status = if ($s2Pass) { "pass" } else { "fail" }
$s2Notes = "exit=$s2Exit; report=$(Fallback-String -Value $s2Report); bootstrap_pass=$s2Bootstrap; session_stable=$s2Stable; fatal_hits=$s2FatalHits"
Add-Result -ScenarioId "P3-FTE-KTX-BOOTSTRAP" -Status $s2Status -Evidence (Fallback-String -Value $s2Report -Fallback $runDir) -Notes $s2Notes

$csvPath = Join-Path $runDir "phase3_validation_matrix.csv"
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
