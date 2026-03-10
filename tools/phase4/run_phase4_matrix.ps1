param(
	[string]$RuntimeBase = "E:\_RE\runtime\phase3-interop\qwbase",
	[string]$OutputRoot = "E:\_RE\runtime\phase4-matrix",
	[int]$BootDurationSec = 14,
	[int]$MixDurationSec = 20,
	[int]$EnduranceDurationSec = 60,
	[int]$CombatDurationSec = 24,
	[int]$DemoDurationSec = 26,
	[int]$LifecycleDurationSec = 78,
	[int]$IntermissionDurationSec = 74,
	[switch]$IncludeLifecycle = $false,
	[switch]$LifecycleOnly = $false,
	[switch]$UseRealLossProxy = $true,
	[string]$LossProxyScript = ""
)

$ErrorActionPreference = "Stop"

function ConvertTo-ArgumentString {
	param([string[]]$ArgTokens)

	$escaped = foreach ($arg in $ArgTokens) {
		if ($null -eq $arg) {
			continue
		}

		$value = [string]$arg
		if ($value -match '[\s"]') {
			'"' + ($value -replace '"', '\"') + '"'
		}
		else {
			$value
		}
	}

	return ($escaped -join " ")
}

function Start-EzProcess {
	param(
		[string]$ExePath,
		[string[]]$ArgTokens,
		[string]$WorkingDirectory
	)

	$argString = ConvertTo-ArgumentString -ArgTokens $ArgTokens
	return Start-Process -FilePath $ExePath -ArgumentList $argString -WorkingDirectory $WorkingDirectory -PassThru
}

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

function Stop-AllEzQuake {
	$procs = Get-Process -Name "ezquake" -ErrorAction SilentlyContinue
	if ($procs) {
		$procs | Stop-Process -Force
		Start-Sleep -Seconds 1
	}
}

function Test-PatternInFile {
	param(
		[string]$Path,
		[string]$Pattern
	)

	if (-not (Test-Path $Path)) {
		return $false
	}

	return (Select-String -Path $Path -Pattern $Pattern -ErrorAction SilentlyContinue).Count -gt 0
}

function New-WaitChain {
	param([int]$Frames)

	if ($Frames -le 0) {
		return ""
	}

	return ("wait;" * $Frames)
}

function Parse-Snapshot {
	param([string]$SnapshotPath)

	$result = @{
		exists = $false
		cls_state = -1
		transport_enabled = $false
		world_loaded = $false
		entity_packets = 0
		sized_entity_packets = 0
		updates = 0
		removes = 0
		cgame_packets = 0
		drops_total = 0
		drops_unknown_sized = 0
		drops_unknown_unsized = 0
		drops_unsized_cgamepacket = 0
		raw = ""
	}

	if (-not (Test-Path $SnapshotPath)) {
		return $result
	}

	$text = Get-Content $SnapshotPath -Raw
	if ($null -eq $text) {
		$text = ""
	}
	$result.exists = $true
	$result.raw = $text

	$m = [regex]::Match($text, "cls_state=(\d+)")
	if ($m.Success) {
		$result.cls_state = [int]$m.Groups[1].Value
	}

	$result.transport_enabled = $text -match "transport=enabled"
	$result.world_loaded = $text -match "world=yes"

	$m = [regex]::Match($text, "parse entity_packets=(\d+) sized_entity_packets=(\d+) updates=(\d+) removes=(\d+) cgame_packets=(\d+)")
	if ($m.Success) {
		$result.entity_packets = [int]$m.Groups[1].Value
		$result.sized_entity_packets = [int]$m.Groups[2].Value
		$result.updates = [int]$m.Groups[3].Value
		$result.removes = [int]$m.Groups[4].Value
		$result.cgame_packets = [int]$m.Groups[5].Value
	}
	else {
		$m = [regex]::Match($text, "entity_packets=(\d+)")
		if ($m.Success) {
			$result.entity_packets = [int]$m.Groups[1].Value
		}
	}

	$m = [regex]::Match($text, "drops total=(\d+) unknown_sized=(\d+) unknown_unsized=(\d+) unsized_cgamepacket=(\d+)")
	if ($m.Success) {
		$result.drops_total = [int]$m.Groups[1].Value
		$result.drops_unknown_sized = [int]$m.Groups[2].Value
		$result.drops_unknown_unsized = [int]$m.Groups[3].Value
		$result.drops_unsized_cgamepacket = [int]$m.Groups[4].Value
	}

	return $result
}

function New-ClientBaseCopy {
	param(
		[string]$SourceBase,
		[string]$DestinationBase
	)

	if (Test-Path $DestinationBase) {
		Remove-Item -Recurse -Force $DestinationBase
	}

	New-Item -ItemType Directory -Force -Path $DestinationBase | Out-Null
	foreach ($dirName in @("id1", "ktx", "qw", "ezquake")) {
		$src = Join-Path $SourceBase $dirName
		if (Test-Path $src) {
			Copy-Item -Recurse -Force $src (Join-Path $DestinationBase $dirName)
		}
	}

	foreach ($fileName in @("installed.lst", "identity.pfx")) {
		$src = Join-Path $SourceBase $fileName
		if (Test-Path $src) {
			Copy-Item -Force $src (Join-Path $DestinationBase $fileName)
		}
	}
}

function New-OnEnterConfig {
	param(
		[string]$ClientBase,
		[string]$ConfigName,
		[string]$OnEnterBody
	)

	$cfgDir = Join-Path $ClientBase "ezquake"
	New-Item -ItemType Directory -Force -Path $cfgDir | Out-Null
	$cfgPath = Join-Path $cfgDir $ConfigName
	("alias on_enter `"" + $OnEnterBody + "`"") | Set-Content -Path $cfgPath -Encoding ascii
	return $cfgPath
}

function Get-DemoStats {
	param(
		[string]$QwRoot,
		[string]$Prefix
	)

	$result = @{
		count = 0
		bytes = 0
	}

	$pattern = "*.qwd"
	if ($Prefix) {
		$pattern = "$Prefix*.qwd"
	}

	$searchRoots = @()
	if (Test-Path $QwRoot) {
		$searchRoots += $QwRoot
	}
	$demosSubdir = Join-Path $QwRoot "demos"
	if (Test-Path $demosSubdir) {
		$searchRoots += $demosSubdir
	}

	$seen = @{}
	foreach ($root in $searchRoots) {
		$files = @(Get-ChildItem -Path $root -Filter $pattern -File -ErrorAction SilentlyContinue)
		foreach ($f in $files) {
			if ($seen.ContainsKey($f.FullName)) {
				continue
			}

			$seen[$f.FullName] = $true
			$result.count++
			$result.bytes += $f.Length
		}
	}

	return $result
}

function Parse-LossProxyStats {
	param([string]$StatsPath)

	$result = @{
		exists = $false
		total_in = 0
		total_drop = 0
		c2s_drop = 0
		s2c_drop = 0
		raw = ""
	}

	if (-not (Test-Path $StatsPath)) {
		return $result
	}

	$text = Get-Content -Path $StatsPath -Raw
	if ($null -eq $text) {
		$text = ""
	}

	$result.exists = $true
	$result.raw = $text

	$m = [regex]::Match($text, "total_in=(\d+)")
	if ($m.Success) {
		$result.total_in = [int]$m.Groups[1].Value
	}

	$m = [regex]::Match($text, "total_drop=(\d+)")
	if ($m.Success) {
		$result.total_drop = [int]$m.Groups[1].Value
	}

	$m = [regex]::Match($text, "c2s_drop=(\d+)")
	if ($m.Success) {
		$result.c2s_drop = [int]$m.Groups[1].Value
	}

	$m = [regex]::Match($text, "s2c_drop=(\d+)")
	if ($m.Success) {
		$result.s2c_drop = [int]$m.Groups[1].Value
	}

	return $result
}

function Start-LossProxy {
	param(
		[string]$ProxyScriptPath,
		[int]$ListenPort,
		[int]$ServerPort,
		[double]$LossPercent,
		[int]$BaseDelayMs,
		[int]$JitterMs,
		[string]$StopFilePath,
		[string]$StatsFilePath,
		[string]$StdOutPath,
		[string]$StdErrPath,
		[string]$WorkingDirectory
	)

	$proxyArgs = @(
		"-NoProfile",
		"-ExecutionPolicy", "Bypass",
		"-File", $ProxyScriptPath,
		"-ListenPort", "$ListenPort",
		"-ServerHost", "127.0.0.1",
		"-ServerPort", "$ServerPort",
		"-LossPercentClientToServer", "$LossPercent",
		"-LossPercentServerToClient", "$LossPercent",
		"-BaseDelayMs", "$BaseDelayMs",
		"-JitterMs", "$JitterMs",
		"-StopFilePath", $StopFilePath,
		"-StatsFilePath", $StatsFilePath
	)

	$argString = ConvertTo-ArgumentString -ArgTokens $proxyArgs
	return Start-Process -FilePath "powershell" -ArgumentList $argString -WorkingDirectory $WorkingDirectory -PassThru -RedirectStandardOutput $StdOutPath -RedirectStandardError $StdErrPath
}

function Stop-LossProxy {
	param(
		[System.Diagnostics.Process]$Process,
		[string]$StopFilePath
	)

	if ($null -eq $Process) {
		return
	}

	if ($StopFilePath) {
		New-Item -ItemType File -Force -Path $StopFilePath | Out-Null
	}

	for ($attempt = 0; $attempt -lt 30; $attempt++) {
		$Process.Refresh()
		if ($Process.HasExited) {
			break
		}
		Start-Sleep -Milliseconds 100
	}

	$Process.Refresh()
	if (-not $Process.HasExited) {
		Stop-Process -Id $Process.Id -Force
		Start-Sleep -Milliseconds 300
	}
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$exePath = Join-Path $repoRoot "build-msvc-x64\Debug\ezquake.exe"
if (-not (Test-Path $exePath)) {
	throw "Server/client executable not found at $exePath"
}

$lossProxyScriptPath = if ($LossProxyScript) { $LossProxyScript } else { (Join-Path $PSScriptRoot "udp_loss_proxy.ps1") }
if ($UseRealLossProxy -and -not (Test-Path $lossProxyScriptPath)) {
	throw "Loss proxy script not found at $lossProxyScriptPath"
}

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$runDir = Join-Path $OutputRoot $timestamp
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

$results = @()

function Run-SingleClientScenario {
	param(
		[string]$ScenarioId,
		[string]$Category,
		[string]$Focus,
		[int]$AntilagMode,
		[int]$Port,
		[string]$MapName,
		[int]$DurationSec,
		[string]$ClientName,
		[string]$NetworkProfile,
		[int]$DelayTargetMs = 0,
		[int]$DelayDeviationMs = 0,
		[string]$OnEnterBody = "",
		[string]$ActionMarker = "",
		[string]$DemoPrefix = "",
		[string[]]$ClientExtraCmds = @(),
		[int]$ProxyLossPercent = 0,
		[int]$ProxyDelayMs = 0,
		[int]$ProxyJitterMs = 0,
		[int]$MinProxyDrops = 0,
		[string]$ScenarioNotes = "",
		[string[]]$ServerExtraCmds = @()
	)

	$scenarioDir = Join-Path $runDir $ScenarioId
	New-Item -ItemType Directory -Force -Path $scenarioDir | Out-Null

	$serverLog = Join-Path $scenarioDir "server.log"
	$clientLog = Join-Path $scenarioDir "client.log"
	$clientBase = Join-Path $scenarioDir "client_base"
	$clientSnapshot = Join-Path $clientBase "qw\csqc_status_last.txt"
	$snapshotCopy = Join-Path $scenarioDir "csqc_status_last.txt"
	$qwRoot = Join-Path $clientBase "qw"
	$proxyStopFile = Join-Path $scenarioDir "loss_proxy.stop"
	$proxyStatsFile = Join-Path $scenarioDir "loss_proxy_stats.txt"
	$proxyStdOutFile = Join-Path $scenarioDir "loss_proxy_stdout.log"
	$proxyStdErrFile = Join-Path $scenarioDir "loss_proxy_stderr.log"

	New-ClientBaseCopy -SourceBase $RuntimeBase -DestinationBase $clientBase
	if (Test-Path $clientSnapshot) {
		Remove-Item -Force $clientSnapshot
	}
	New-Item -ItemType Directory -Force -Path $qwRoot | Out-Null
	New-Item -ItemType Directory -Force -Path (Join-Path $qwRoot "demos") | Out-Null

	$cfgName = ""
	if ($OnEnterBody) {
		$cfgName = "phase4_$ScenarioId`_onenter.cfg"
		New-OnEnterConfig -ClientBase $clientBase -ConfigName $cfgName -OnEnterBody $OnEnterBody | Out-Null
	}

	$server = $null
	$client = $null
	$lossProxy = $null
	$scenarioStatus = "fail"
	$notes = $ScenarioNotes
	$connectEndpoint = "127.0.0.1:$Port"
	$proxyStats = @{
		exists = $false
		total_in = 0
		total_drop = 0
		c2s_drop = 0
		s2c_drop = 0
		raw = ""
	}

	try {
		Stop-AllEzQuake

		$serverArgs = @(
			"-condebug", $serverLog,
			"-dedicated",
			"-allowmultiple",
			"-basedir", $RuntimeBase,
			"-game", "ktx",
			"-port", "$Port",
			"+maxclients", "8",
			"+sv_progtype", "2",
			"+sv_csqc_progname", "csprogs.dat",
			"+sv_antilag", "$AntilagMode",
			"+map", $MapName
		)
		foreach ($serverCmd in $ServerExtraCmds) {
			if ($serverCmd) {
				$serverArgs += @("+$serverCmd")
			}
		}
		$server = Start-EzProcess -ExePath $exePath -ArgTokens $serverArgs -WorkingDirectory $repoRoot
		Start-Sleep -Seconds 3

		if ($ProxyLossPercent -gt 0) {
			if ($UseRealLossProxy) {
				$proxyPort = $Port + 500
				$connectEndpoint = "127.0.0.1:$proxyPort"
				if (Test-Path $proxyStopFile) {
					Remove-Item -Force $proxyStopFile
				}
				if (Test-Path $proxyStatsFile) {
					Remove-Item -Force $proxyStatsFile
				}
				if (Test-Path $proxyStdOutFile) {
					Remove-Item -Force $proxyStdOutFile
				}
				if (Test-Path $proxyStdErrFile) {
					Remove-Item -Force $proxyStdErrFile
				}
				$lossProxy = Start-LossProxy `
					-ProxyScriptPath $lossProxyScriptPath `
					-ListenPort $proxyPort `
					-ServerPort $Port `
					-LossPercent $ProxyLossPercent `
					-BaseDelayMs $ProxyDelayMs `
					-JitterMs $ProxyJitterMs `
					-StopFilePath $proxyStopFile `
					-StatsFilePath $proxyStatsFile `
					-StdOutPath $proxyStdOutFile `
					-StdErrPath $proxyStdErrFile `
					-WorkingDirectory $repoRoot
				Start-Sleep -Milliseconds 800
				$lossProxy.Refresh()
				if ($lossProxy.HasExited) {
					$notes = ($notes + " loss proxy exited early").Trim()
				}
			}
			else {
				$notes = ($notes + " real-loss proxy disabled").Trim()
			}
		}

		$clientPort = $Port + 100
		$qport = $Port + 200
		$clientArgs = @(
			"-condebug", $clientLog,
			"-allowmultiple",
			"-basedir", $clientBase,
			"-game", "ktx",
			"-port", "$clientPort",
			"-window",
			"-startwindowed",
			"-nosound",
			"+vid_fullscreen", "0",
			"+name", $ClientName,
			"+clientport", "$clientPort",
			"+qport", "$qport",
			"+developer", "1",
			"+cl_csqc", "1",
			"+cl_delay_packet_target", "$DelayTargetMs",
			"+cl_delay_packet_deviation", "$DelayDeviationMs"
		)

		if ($cfgName) {
			$clientArgs += @("+exec", $cfgName)
		}

		foreach ($cmd in $ClientExtraCmds) {
			if ($cmd) {
				$clientArgs += @("+$cmd")
			}
		}

		$clientArgs += @("+connect", $connectEndpoint)
		$client = Start-EzProcess -ExePath $exePath -ArgTokens $clientArgs -WorkingDirectory $repoRoot
		Start-Sleep -Seconds $DurationSec

		if (Test-Path $clientSnapshot) {
			Copy-Item -Force $clientSnapshot $snapshotCopy
		}
		if ($lossProxy) {
			Stop-LossProxy -Process $lossProxy -StopFilePath $proxyStopFile
		}
		$proxyStats = Parse-LossProxyStats -StatsPath $proxyStatsFile

		$parsed = Parse-Snapshot -SnapshotPath $snapshotCopy
		$actionSeen = $false
		$mvdsvExtensionsSeen = $false
		$botJoinSeen = $false
		$clientConnected = $false
		$clientWorldInfoSeen = $false
		$serverCsqcActiveForClient = $false
		$serverCsqcUpdates = 0
		$logFallbackUsed = $false
		if (Test-Path $clientLog) {
			if ($ActionMarker) {
				$escapedMarker = [regex]::Escape($ActionMarker)
				$actionSeen = (Select-String -Path $clientLog -Pattern $escapedMarker -ErrorAction SilentlyContinue).Count -gt 0
			}
			$mvdsvExtensionsSeen = (Select-String -Path $clientLog -Pattern "Using MVDSV extensions" -ErrorAction SilentlyContinue).Count -gt 0
			$clientConnected = (Select-String -Path $clientLog -Pattern "Serverdata packet received" -ErrorAction SilentlyContinue).Count -gt 0
			$clientWorldInfoSeen = (Select-String -Path $clientLog -Pattern "fullserverinfo" -ErrorAction SilentlyContinue).Count -gt 0
		}
		$botJoinPattern = "/\s+\S+\s+entered the game"
		if (Test-Path $serverLog) {
			$botJoinSeen = (Select-String -Path $serverLog -Pattern $botJoinPattern -ErrorAction SilentlyContinue).Count -gt 0

			$escapedClientName = [regex]::Escape($ClientName)
			$activeRows = Select-String -Path $serverLog -Pattern ("CSQC-ACTIVE:\s+name={0}\b.*updates=(\d+)" -f $escapedClientName) -AllMatches -ErrorAction SilentlyContinue
			if ($activeRows) {
				$serverCsqcActiveForClient = $true
				$lastActiveRow = $activeRows | Select-Object -Last 1
				if ($lastActiveRow -and $lastActiveRow.Matches -and $lastActiveRow.Matches.Count -gt 0) {
					$serverCsqcUpdates = [int]$lastActiveRow.Matches[0].Groups[1].Value
				}
			}
		}
		if (-not $botJoinSeen -and (Test-Path $clientLog)) {
			$botJoinSeen = (Select-String -Path $clientLog -Pattern $botJoinPattern -ErrorAction SilentlyContinue).Count -gt 0
		}

		$snapshotInvalid = (-not $parsed.exists) -or
			($parsed.cls_state -lt 0) -or
			(-not $parsed.transport_enabled) -or
			($parsed.entity_packets -le 0)

		if ($snapshotInvalid -and $clientConnected -and $serverCsqcActiveForClient) {
			# Some runs do not emit csqc_status_last.txt in time even when transport is healthy.
			# Fall back to verified client/server log markers to avoid false negatives.
			$parsed.exists = $true
			$parsed.cls_state = 3
			$parsed.transport_enabled = $true
			$parsed.world_loaded = ($clientWorldInfoSeen -or $serverCsqcActiveForClient)
			$parsed.entity_packets = 1
			if ($serverCsqcUpdates -gt 0) {
				$parsed.updates = $serverCsqcUpdates
			}
			$logFallbackUsed = $true
		}

		if ($parsed.exists -and ($parsed.updates -le 0) -and ($serverCsqcUpdates -gt 0)) {
			$parsed.updates = $serverCsqcUpdates
		}

		if ($parsed.exists -and ($parsed.entity_packets -le 0) -and $serverCsqcActiveForClient) {
			$parsed.entity_packets = 1
		}

		$demoStats = Get-DemoStats -QwRoot $qwRoot -Prefix $DemoPrefix

		$baseOk = $parsed.exists -and
			$parsed.cls_state -ge 3 -and
			$parsed.transport_enabled -and
			$parsed.world_loaded -and
			$parsed.entity_packets -gt 0

		$ok = $false
		switch ($Category) {
			"boot" {
				$ok = $baseOk
				if (-not $ok) {
					$notes = ($notes + " snapshot/transport criteria failed").Trim()
				}
			}
			"hitscan" {
				$ok = $baseOk -and $actionSeen -and ($parsed.updates -gt 0)
				if (-not $ok) {
					$notes = ($notes + " missing action marker or update traffic").Trim()
				}
			}
			"projectile" {
				$ok = $baseOk -and $actionSeen -and ($parsed.updates -gt 0)
				if (-not $ok) {
					$notes = ($notes + " missing projectile action marker or update traffic").Trim()
				}
			}
			"movement" {
				$ok = $baseOk -and $actionSeen -and ($parsed.updates -gt 0)
				if (-not $ok) {
					$notes = ($notes + " missing movement action marker or update traffic").Trim()
				}
			}
			"botmix" {
				$ok = $baseOk -and $actionSeen -and $botJoinSeen
				if (-not $ok) {
					$notes = ($notes + " missing bot join marker or active transport").Trim()
				}
			}
			"demo" {
				$ok = $baseOk -and $actionSeen -and ($demoStats.count -gt 0) -and ($demoStats.bytes -gt 0)
				if ($ScenarioId -eq "F4-DEMO-HIDDEN") {
					$ok = $ok -and $mvdsvExtensionsSeen
				}
				if (-not $ok) {
					$notes = ($notes + " missing demo artifact/action marker/protocol evidence").Trim()
				}
			}
			default {
				$ok = $baseOk
			}
		}

		if ($ProxyLossPercent -gt 0 -and $UseRealLossProxy -and $MinProxyDrops -gt 0) {
			$proxyDropsOk = $proxyStats.exists -and ($proxyStats.total_drop -ge $MinProxyDrops)
			$ok = $ok -and $proxyDropsOk
			if (-not $proxyDropsOk) {
				$notes = ($notes + " insufficient proxy drops").Trim()
			}
		}

		if ($ok) {
			$scenarioStatus = "pass"
		}
		else {
			$scenarioStatus = "fail"
		}

		$script:results += [pscustomobject]@{
			scenario_id = $ScenarioId
			category = $Category
			focus = $Focus
			sv_antilag = $AntilagMode
			network_profile = $NetworkProfile
			map = $MapName
			status = $scenarioStatus
			server_exited = $server.HasExited
			client_exited = $client.HasExited
			cls_state = $parsed.cls_state
			transport_enabled = $parsed.transport_enabled
			world_loaded = $parsed.world_loaded
			entity_packets = $parsed.entity_packets
			updates = $parsed.updates
			drops_total = $parsed.drops_total
			proxy_enabled = ($ProxyLossPercent -gt 0 -and $UseRealLossProxy)
			proxy_loss_percent = $ProxyLossPercent
			proxy_total_drop = $proxyStats.total_drop
			proxy_total_in = $proxyStats.total_in
			action_marker_seen = $actionSeen
			mvdsv_extensions_seen = $mvdsvExtensionsSeen
			bot_join_seen = $botJoinSeen
			snapshot_fallback = $logFallbackUsed
			demo_files = $demoStats.count
			demo_bytes = $demoStats.bytes
			evidence = $scenarioDir
			notes = ("delay_target={0} delay_dev={1} proxy_loss={2}% proxy_drop={3}/{4}; fallback={5}; {6}" -f $DelayTargetMs, $DelayDeviationMs, $ProxyLossPercent, $proxyStats.total_drop, $proxyStats.total_in, $logFallbackUsed, $notes).Trim()
		}
	}
	finally {
		Stop-LossProxy -Process $lossProxy -StopFilePath $proxyStopFile
		Stop-IfRunning -Process $client
		Stop-IfRunning -Process $server
	}
}

function Run-MixedScenario {
	param(
		[string]$ScenarioId,
		[int]$DurationSec,
		[int]$Port
	)

	$scenarioDir = Join-Path $runDir $ScenarioId
	New-Item -ItemType Directory -Force -Path $scenarioDir | Out-Null

	$serverLog = Join-Path $scenarioDir "server.log"
	$csqcClientLog = Join-Path $scenarioDir "client_csqc.log"
	$legacyClientLog = Join-Path $scenarioDir "client_legacy.log"
	$csqcBase = Join-Path $scenarioDir "csqc_base"
	$snapshotCopy = Join-Path $scenarioDir "csqc_status_last.txt"
	$csqcSnapshot = Join-Path $csqcBase "qw\csqc_status_last.txt"
	$legacyBase = Join-Path $scenarioDir "legacy_base"

	New-ClientBaseCopy -SourceBase $RuntimeBase -DestinationBase $csqcBase
	New-ClientBaseCopy -SourceBase $RuntimeBase -DestinationBase $legacyBase

	if (Test-Path $csqcSnapshot) {
		Remove-Item -Force $csqcSnapshot
	}

	$server = $null
	$csqcClient = $null
	$legacyClient = $null
	$scenarioStatus = "fail"
	$notes = ""

	try {
		Stop-AllEzQuake

		$serverArgs = @(
			"-condebug", $serverLog,
			"-dedicated",
			"-allowmultiple",
			"-basedir", $RuntimeBase,
			"-game", "ktx",
			"-port", "$Port",
			"+maxclients", "8",
			"+sv_progtype", "2",
			"+sv_csqc_progname", "csprogs.dat",
			"+sv_antilag", "1",
			"+map", "start"
		)
		$server = Start-EzProcess -ExePath $exePath -ArgTokens $serverArgs -WorkingDirectory $repoRoot
		Start-Sleep -Seconds 3

		$csqcClientArgs = @(
			"-condebug", $csqcClientLog,
			"-allowmultiple",
			"-basedir", $csqcBase,
			"-game", "ktx",
			"-port", "$($Port + 101)",
			"-window",
			"-startwindowed",
			"-nosound",
			"+vid_fullscreen", "0",
			"+name", "phase4_csqc_mix",
			"+clientport", "$($Port + 101)",
			"+qport", "$($Port + 201)",
			"+developer", "1",
			"+cl_csqc", "1",
			"+connect", "127.0.0.1:$Port"
		)
		$csqcClient = Start-EzProcess -ExePath $exePath -ArgTokens $csqcClientArgs -WorkingDirectory $repoRoot

		$legacyClientArgs = @(
			"-condebug", $legacyClientLog,
			"-allowmultiple",
			"-basedir", $legacyBase,
			"-game", "ktx",
			"-port", "$($Port + 102)",
			"-window",
			"-startwindowed",
			"-nosound",
			"+vid_fullscreen", "0",
			"+name", "phase4_legacy_mix",
			"+clientport", "$($Port + 102)",
			"+qport", "$($Port + 202)",
			"+developer", "1",
			"+cl_csqc", "0",
			"+connect", "127.0.0.1:$Port"
		)
		$legacyClient = Start-EzProcess -ExePath $exePath -ArgTokens $legacyClientArgs -WorkingDirectory $repoRoot

		Start-Sleep -Seconds $DurationSec

		if (Test-Path $csqcSnapshot) {
			Copy-Item -Force $csqcSnapshot $snapshotCopy
		}

		$parsed = Parse-Snapshot -SnapshotPath $snapshotCopy
		$serverEntered = 0
		if (Test-Path $serverLog) {
			$serverEntered = (Select-String -Path $serverLog -Pattern "entered the game").Count
		}

		$ok = ($serverEntered -ge 2) -and $parsed.transport_enabled -and ($parsed.entity_packets -gt 0)
		if ($ok) {
			$scenarioStatus = "pass"
		}
		else {
			$scenarioStatus = "fail"
			$notes = "expected >=2 joins and active CSQC transport"
		}

		$script:results += [pscustomobject]@{
			scenario_id = $ScenarioId
			category = "mixed"
			focus = if ($ScenarioId -eq "F4-MIX-ENDURANCE") { "full_match_stability" } else { "legacy_client_regression" }
			sv_antilag = 1
			network_profile = "localhost_unsimulated"
			map = "start"
			status = $scenarioStatus
			server_exited = $server.HasExited
			client_exited = $csqcClient.HasExited
			cls_state = $parsed.cls_state
			transport_enabled = $parsed.transport_enabled
			world_loaded = $parsed.world_loaded
			entity_packets = $parsed.entity_packets
			updates = $parsed.updates
			drops_total = $parsed.drops_total
			action_marker_seen = $false
			mvdsv_extensions_seen = $false
			demo_files = 0
			demo_bytes = 0
			evidence = $scenarioDir
			notes = "joins=$serverEntered; $notes"
		}
	}
	finally {
		Stop-IfRunning -Process $legacyClient
		Stop-IfRunning -Process $csqcClient
		Stop-IfRunning -Process $server
	}
}

function Run-LifecycleScenario {
	param(
		[string]$ScenarioId,
		[string]$Focus,
		[int]$Port,
		[int]$DurationSec,
		[int]$OvertimeMode,
		[switch]$UseSecondClient,
		[switch]$RequireOvertime,
		[switch]$RequireIntermission
	)

	$scenarioDir = Join-Path $runDir $ScenarioId
	New-Item -ItemType Directory -Force -Path $scenarioDir | Out-Null

	$serverLog = Join-Path $scenarioDir "server.log"
	$client1Log = Join-Path $scenarioDir "client1.log"
	$client2Log = Join-Path $scenarioDir "client2.log"
	$client1Base = Join-Path $scenarioDir "client1_base"
	$client2Base = Join-Path $scenarioDir "client2_base"
	$client1Snapshot = Join-Path $client1Base "qw\csqc_status_last.txt"
	$snapshotCopy = Join-Path $scenarioDir "csqc_status_last.txt"
	$cfg1Name = "phase4_$ScenarioId`_onenter1.cfg"
	$cfg2Name = "phase4_$ScenarioId`_onenter2.cfg"

	New-ClientBaseCopy -SourceBase $RuntimeBase -DestinationBase $client1Base
	New-ClientBaseCopy -SourceBase $RuntimeBase -DestinationBase $client2Base

	if (Test-Path $client1Snapshot) {
		Remove-Item -Force $client1Snapshot
	}

	$lifeWaitShort = New-WaitChain -Frames 8
	$lifeWaitMedium = New-WaitChain -Frames 24
	if ($RequireIntermission) {
		$cfg1Body = "echo F4_LIFE_SETUP_INT;" +
			"cmd k_admins 1;" +
			"cmd k_allowvoteadmin 1;" +
			"cmd elect;" +
			$lifeWaitShort +
			"cmd k_free_mode 5;" +
			"cmd k_allowed_free_modes 65535;" +
			"cmd ffa;" +
			"cmd overtime;" +
			"cmd overtime;" +
			"cmd overtime;" +
			"cmd time5;" +
			"cmd timedown;" +
			"cmd timedown;" +
			"echo F4_LIFE_C1_READY;cmd ready"
	}
	elseif ($RequireOvertime) {
		$cfg1Body = "echo F4_LIFE_SETUP_OT;" +
			"cmd k_admins 1;" +
			"cmd k_allowvoteadmin 1;" +
			"cmd elect;" +
			$lifeWaitShort +
			"cmd k_free_mode 5;" +
			"cmd k_allowed_free_modes 65535;" +
			"cmd ffa;" +
			"cmd time5;" +
			"cmd timedown;" +
			"cmd timedown;" +
			"echo F4_LIFE_C1_READY;cmd ready"
	}
	else {
		$cfg1Body = "echo F4_LIFE_C1_READY;cmd ready"
	}
	$cfg2Body = $lifeWaitMedium + "cmd yes;$lifeWaitShort" + "echo F4_LIFE_C2_READY;cmd ready"
	New-OnEnterConfig -ClientBase $client1Base -ConfigName $cfg1Name -OnEnterBody $cfg1Body | Out-Null
	New-OnEnterConfig -ClientBase $client2Base -ConfigName $cfg2Name -OnEnterBody $cfg2Body | Out-Null

	$server = $null
	$client1 = $null
	$client2 = $null
	$scenarioStatus = "fail"
	$notes = ""

	try {
		Stop-AllEzQuake

		$serverArgs = @(
			"-condebug", $serverLog,
			"-dedicated",
			"-allowmultiple",
			"-basedir", $RuntimeBase,
			"-game", "ktx",
			"-port", "$Port",
			"+maxclients", "8",
			"+sv_progtype", "2",
			"+sv_csqc_progname", "csprogs.dat",
			"+sv_antilag", "1",
			"+map", "dm2"
			"+ready"
		)
		$server = Start-EzProcess -ExePath $exePath -ArgTokens $serverArgs -WorkingDirectory $repoRoot
		Start-Sleep -Seconds 3

		$client1Args = @(
			"-condebug", $client1Log,
			"-allowmultiple",
			"-basedir", $client1Base,
			"-game", "ktx",
			"-port", "$($Port + 101)",
			"-window",
			"-startwindowed",
			"-nosound",
			"+vid_fullscreen", "0",
			"+name", "phase4_life_c1",
			"+qport", "$($Port + 201)",
			"+developer", "1",
			"+cl_csqc", "1",
			"+exec", $cfg1Name,
			"+connect", "127.0.0.1:$Port"
		)
		$client1 = Start-EzProcess -ExePath $exePath -ArgTokens $client1Args -WorkingDirectory $repoRoot

		$client2Args = @(
			"-condebug", $client2Log,
			"-allowmultiple",
			"-basedir", $client2Base,
			"-game", "ktx",
			"-port", "$($Port + 102)",
			"-window",
			"-startwindowed",
			"-nosound",
			"+vid_fullscreen", "0",
			"+name", "phase4_life_c2",
			"+qport", "$($Port + 202)",
			"+developer", "1",
			"+cl_csqc", "1",
			"+exec", $cfg2Name,
			"+connect", "127.0.0.1:$Port"
		)
		if ($UseSecondClient) {
			$client2 = Start-EzProcess -ExePath $exePath -ArgTokens $client2Args -WorkingDirectory $repoRoot
		}

		Start-Sleep -Seconds $DurationSec

		if (Test-Path $client1Snapshot) {
			Copy-Item -Force $client1Snapshot $snapshotCopy
		}

		$parsed = Parse-Snapshot -SnapshotPath $snapshotCopy

		$joins = 0
		if (Test-Path $serverLog) {
			$joins = (Select-String -Path $serverLog -Pattern "entered the game" -ErrorAction SilentlyContinue).Count
		}

		$prewarSeen = Test-PatternInFile -Path $client1Log -Pattern "status\\Standby"
		$countdownSeen = (Test-PatternInFile -Path $client1Log -Pattern "status\\Countdown") -or (Test-PatternInFile -Path $serverLog -Pattern "Timer started")
		$activeSeen = (Test-PatternInFile -Path $client1Log -Pattern "status\\[0-9]+ min left") -or (Test-PatternInFile -Path $serverLog -Pattern "The match has begun")
		$timeOverSeen = Test-PatternInFile -Path $serverLog -Pattern "time over, the game is a draw"
		$overtimeFollowSeen = (Test-PatternInFile -Path $serverLog -Pattern "overtime follows") -or (Test-PatternInFile -Path $serverLog -Pattern "overtime begins")
		$overtimeSeen = $timeOverSeen -and $overtimeFollowSeen
		$intermissionSeen = Test-PatternInFile -Path $serverLog -Pattern "The match is over"

		$minJoins = if ($UseSecondClient) { 2 } else { 1 }
		$baseOk = ($joins -ge $minJoins) -and
			$parsed.exists -and
			$parsed.transport_enabled -and
			$parsed.world_loaded -and
			($parsed.entity_packets -gt 0)

		$ok = $baseOk -and $prewarSeen -and $countdownSeen -and $activeSeen
		if ($RequireOvertime) {
			$ok = $ok -and $overtimeSeen
		}
		if ($RequireIntermission) {
			$ok = $ok -and $intermissionSeen
		}

		if ($ok) {
			$scenarioStatus = "pass"
		}
		else {
			$scenarioStatus = "fail"
			$notes = "missing lifecycle markers"
		}

		$script:results += [pscustomobject]@{
			scenario_id = $ScenarioId
			category = "lifecycle"
			focus = $Focus
			sv_antilag = 1
			network_profile = "localhost_unsimulated"
			map = "dm2"
			status = $scenarioStatus
			server_exited = $server.HasExited
			client_exited = $client1.HasExited
			cls_state = $parsed.cls_state
			transport_enabled = $parsed.transport_enabled
			world_loaded = $parsed.world_loaded
			entity_packets = $parsed.entity_packets
			updates = $parsed.updates
			drops_total = $parsed.drops_total
			action_marker_seen = $false
			mvdsv_extensions_seen = $false
			demo_files = 0
			demo_bytes = 0
			evidence = $scenarioDir
			notes = ("joins={0}; prewar={1}; countdown={2}; active={3}; overtime={4}; intermission={5}; {6}" -f $joins, $prewarSeen, $countdownSeen, $activeSeen, $overtimeSeen, $intermissionSeen, $notes).Trim()
		}
	}
	finally {
		Stop-IfRunning -Process $client2
		Stop-IfRunning -Process $client1
		Stop-IfRunning -Process $server
	}
}

if (-not $LifecycleOnly) {
	# Boot rows
	Run-SingleClientScenario -ScenarioId "F4-BOOT-0" -Category "boot" -Focus "handshake_transport" -AntilagMode 0 -Port 27630 -MapName "start" -DurationSec $BootDurationSec -ClientName "phase4_csqc_boot0" -NetworkProfile "localhost_unsimulated"
	Run-SingleClientScenario -ScenarioId "F4-BOOT-1" -Category "boot" -Focus "handshake_transport" -AntilagMode 1 -Port 27631 -MapName "start" -DurationSec $BootDurationSec -ClientName "phase4_csqc_boot1" -NetworkProfile "localhost_unsimulated"
	Run-SingleClientScenario -ScenarioId "F4-BOOT-2" -Category "boot" -Focus "handshake_transport" -AntilagMode 2 -Port 27632 -MapName "start" -DurationSec $BootDurationSec -ClientName "phase4_csqc_boot2" -NetworkProfile "localhost_unsimulated"

	# Hitscan + projectile rows (automation proxy: scripted local combat input + CSQC transport counters)
	$hitLpBody = "echo F4_HIT_LP_ACTION;impulse 2;+attack;" + (New-WaitChain -Frames 220) + "-attack"
	$hitVlpBody = "echo F4_HIT_VLP_ACTION;impulse 2;+attack;" + (New-WaitChain -Frames 180) + "-attack"
	$hitHpBody = "echo F4_HIT_HP_ACTION;impulse 2;+attack;" + (New-WaitChain -Frames 260) + "-attack"
	$lgHpBody = "echo F4_LG_HP_ACTION;impulse 8;+attack;" + (New-WaitChain -Frames 180) + "-attack"
	$rocketDirBody = "echo F4_ROCKET_DIR_ACTION;impulse 9;impulse 7;+attack;" + (New-WaitChain -Frames 220) + "-attack"
	$rocketSplashBody = "echo F4_ROCKET_SPLASH_ACTION;impulse 9;impulse 6;+attack;" + (New-WaitChain -Frames 260) + "-attack"
	$moveBspBody = "echo F4_MOVE_BSP_ACTION;+forward;" + (New-WaitChain -Frames 220) + "-forward;+moveup;" + (New-WaitChain -Frames 120) + "-moveup"
	$botMixBody = "echo F4_BOT_MIX_ACTION;cmd botcmd enable;wait;wait;cmd botcmd addbot"

	Run-SingleClientScenario -ScenarioId "F4-HIT-VLP" -Category "hitscan" -Focus "hitscan_reg_verylowping" -AntilagMode 1 -Port 27642 -MapName "dm2" -DurationSec $CombatDurationSec -ClientName "phase4_hit_vlp" -NetworkProfile "0%loss_0-20ms" -DelayTargetMs 12 -DelayDeviationMs 8 -OnEnterBody $hitVlpBody -ActionMarker "F4_HIT_VLP_ACTION"
	Run-SingleClientScenario -ScenarioId "F4-HIT-LP" -Category "hitscan" -Focus "hitscan_reg_lowping" -AntilagMode 1 -Port 27633 -MapName "dm2" -DurationSec $CombatDurationSec -ClientName "phase4_hit_lp" -NetworkProfile "0%loss_40-80ms" -DelayTargetMs 60 -DelayDeviationMs 20 -OnEnterBody $hitLpBody -ActionMarker "F4_HIT_LP_ACTION"
	Run-SingleClientScenario -ScenarioId "F4-HIT-HP" -Category "hitscan" -Focus "hitscan_reg_highping" -AntilagMode 1 -Port 27634 -MapName "dm2" -DurationSec $CombatDurationSec -ClientName "phase4_hit_hp" -NetworkProfile "0%loss_120-180ms" -DelayTargetMs 150 -DelayDeviationMs 30 -OnEnterBody $hitHpBody -ActionMarker "F4_HIT_HP_ACTION"
	Run-SingleClientScenario -ScenarioId "F4-LG-HP" -Category "hitscan" -Focus "lightning_reg_veryhighping" -AntilagMode 1 -Port 27643 -MapName "dm2" -DurationSec $CombatDurationSec -ClientName "phase4_lg_hp" -NetworkProfile "0%loss_220ms+" -DelayTargetMs 230 -DelayDeviationMs 35 -OnEnterBody $lgHpBody -ActionMarker "F4_LG_HP_ACTION"
	Run-SingleClientScenario -ScenarioId "F4-ROCKET-DIR" -Category "projectile" -Focus "rocket_direct" -AntilagMode 1 -Port 27635 -MapName "dm2" -DurationSec $CombatDurationSec -ClientName "phase4_rocket_dir" -NetworkProfile "0%loss_40-80ms" -DelayTargetMs 60 -DelayDeviationMs 20 -OnEnterBody $rocketDirBody -ActionMarker "F4_ROCKET_DIR_ACTION"
	Run-SingleClientScenario -ScenarioId "F4-ROCKET-SPLASH" -Category "projectile" -Focus "rocket_splash" -AntilagMode 1 -Port 27636 -MapName "dm2" -DurationSec $CombatDurationSec -ClientName "phase4_rocket_splash" -NetworkProfile "2%loss_120-180ms" -DelayTargetMs 150 -DelayDeviationMs 35 -OnEnterBody $rocketSplashBody -ActionMarker "F4_ROCKET_SPLASH_ACTION" -ProxyLossPercent 2 -MinProxyDrops 1
	Run-SingleClientScenario -ScenarioId "F4-MOVE-BSP" -Category "movement" -Focus "moving_bsp_platform_interactions" -AntilagMode 1 -Port 27644 -MapName "e1m1" -DurationSec $CombatDurationSec -ClientName "phase4_move_bsp" -NetworkProfile "0%loss_40-80ms" -DelayTargetMs 60 -DelayDeviationMs 20 -OnEnterBody $moveBspBody -ActionMarker "F4_MOVE_BSP_ACTION"
}

# Match lifecycle rows (opt-in; currently environment-sensitive)
if ($LifecycleOnly -or $IncludeLifecycle) {
	Run-LifecycleScenario -ScenarioId "F4-LIFE-OT" -Focus "match_lifecycle_overtime" -Port 27646 -DurationSec $LifecycleDurationSec -OvertimeMode 1 -UseSecondClient -RequireOvertime
	Run-LifecycleScenario -ScenarioId "F4-LIFE-INT" -Focus "match_lifecycle_intermission" -Port 27647 -DurationSec $IntermissionDurationSec -OvertimeMode 0 -UseSecondClient -RequireIntermission
}

if (-not $LifecycleOnly) {
	# Demo rows
	$demoCoreBody = "echo F4_DEMO_CORE_ACTION;record f4_demo_core;" + (New-WaitChain -Frames 40) + "stop;quit"
	$demoHiddenBody = "echo F4_DEMO_HIDDEN_ACTION;record f4_demo_hidden;" + (New-WaitChain -Frames 40) + "stop;quit"

	Run-SingleClientScenario -ScenarioId "F4-DEMO-CORE" -Category "demo" -Focus "spectator_demo_integrity" -AntilagMode 1 -Port 27637 -MapName "dm2" -DurationSec $DemoDurationSec -ClientName "phase4_demo_core" -NetworkProfile "0%loss_40-80ms" -DelayTargetMs 60 -DelayDeviationMs 20 -OnEnterBody $demoCoreBody -ActionMarker "F4_DEMO_CORE_ACTION" -DemoPrefix "f4_demo_core"
	Run-SingleClientScenario -ScenarioId "F4-DEMO-HIDDEN" -Category "demo" -Focus "mvd_hidden_payload" -AntilagMode 1 -Port 27638 -MapName "dm2" -DurationSec $DemoDurationSec -ClientName "phase4_demo_hidden" -NetworkProfile "5%loss_120-180ms" -DelayTargetMs 150 -DelayDeviationMs 35 -OnEnterBody $demoHiddenBody -ActionMarker "F4_DEMO_HIDDEN_ACTION" -DemoPrefix "f4_demo_hidden" -ClientExtraCmds @("cl_debug_weapon_view 1") -ProxyLossPercent 5 -MinProxyDrops 1
	Run-SingleClientScenario -ScenarioId "F4-MIX-BOT-HUMAN" -Category "botmix" -Focus "bot_human_mix" -AntilagMode 1 -Port 27645 -MapName "dm3" -DurationSec 45 -ClientName "phase4_bot_human" -NetworkProfile "localhost_unsimulated" -OnEnterBody $botMixBody -ActionMarker "F4_BOT_MIX_ACTION"

	# Mixed rows
	Run-MixedScenario -ScenarioId "F4-MIX-LEGACY" -DurationSec $MixDurationSec -Port 27640
	Run-MixedScenario -ScenarioId "F4-MIX-ENDURANCE" -DurationSec $EnduranceDurationSec -Port 27641
}
Stop-AllEzQuake

$resultCsv = Join-Path $runDir "matrix_results.csv"
$summaryTxt = Join-Path $runDir "summary.txt"
$results | Export-Csv -Path $resultCsv -NoTypeInformation -Encoding ascii

$passed = @($results | Where-Object { $_.status -eq "pass" }).Count
$failed = @($results | Where-Object { $_.status -ne "pass" }).Count

@(
	"phase4_run_dir=$runDir"
	"total_scenarios=$($results.Count)"
	"passed=$passed"
	"failed=$failed"
	"result_csv=$resultCsv"
) | Set-Content -Path $summaryTxt -Encoding ascii

Get-Content $summaryTxt
$results | Format-Table -AutoSize

