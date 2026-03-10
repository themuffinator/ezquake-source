param(
	[string]$RuntimeBase = "E:\_RE\runtime\phase3-interop\qwbase",
	[string]$OutputDir = "E:\_RE\runtime\phase2-interop-probe\probe1",
	[int]$Port = 29256,
	[int]$DurationSec = 35,
	[string]$MapName = "dm2",
	[string]$ClientConnectHost = "127.0.0.1",
	[switch]$ForceMatchStart,
	[switch]$SpawnDriverClient,
	[switch]$RouteDriverThroughLossProxy,
	[switch]$RouteFteThroughLossProxy,
	[double]$LossPercent = 0,
	[int]$CsqcDebugDumpBytes = 0,
	[switch]$UseSizedCsqc
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

function Stop-LossProxy {
	param(
		[System.Diagnostics.Process]$Process,
		[string]$StopFile
	)

	if ($null -eq $Process) {
		return
	}

	if ($StopFile) {
		New-Item -ItemType File -Force -Path $StopFile | Out-Null
	}

	for ($i = 0; $i -lt 30; $i++) {
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

function Send-RconCommand {
	param(
		[string]$Address,
		[int]$Port,
		[string]$Password,
		[string]$Command
	)

	$udp = New-Object System.Net.Sockets.UdpClient
	try {
		$target = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Parse($Address), $Port)
		$body = [Text.Encoding]::ASCII.GetBytes("rcon $Password $Command`0")
		$packet = New-Object byte[] (4 + $body.Length)
		$packet[0] = 255
		$packet[1] = 255
		$packet[2] = 255
		$packet[3] = 255
		[Array]::Copy($body, 0, $packet, 4, $body.Length)
		[void]$udp.Send($packet, $packet.Length, $target)
	}
	finally {
		$udp.Close()
	}
}

function Stop-AllTargets {
	Get-Process -Name "ezquake", "fteqw64" -ErrorAction SilentlyContinue | Stop-Process -Force
	Start-Sleep -Seconds 1
}

function Wait-ServerReady {
	param(
		[System.Diagnostics.Process]$Process,
		[string]$ServerLogPath,
		[int]$Port,
		[int]$TimeoutSec = 180
	)

	$readyPattern = "(Server spawned\\.|Init Game)"
	$deadline = (Get-Date).AddSeconds($TimeoutSec)
	while ((Get-Date) -lt $deadline) {
		$Process.Refresh()
		if ($Process.HasExited) {
			return $false
		}

		$isListening = $false
		$portHits = netstat -ano -p udp | Select-String -Pattern (":{0}\s+.*\s+{1}\s*$" -f $Port, $Process.Id) -CaseSensitive:$false -ErrorAction SilentlyContinue
		if ($portHits) {
			$isListening = $true
		}

		if (Test-Path $ServerLogPath) {
			$ready = Select-String -Path $ServerLogPath -Pattern $readyPattern -CaseSensitive:$false -ErrorAction SilentlyContinue | Select-Object -First 1
			if ($ready -and $isListening) {
				return $true
			}
		}

		Start-Sleep -Milliseconds 250
	}

	return $false
}

function Resolve-FteLogPath {
	param([string]$FteBasePath)

	$candidates = @(
		(Join-Path $FteBasePath "fte\qconsole.log"),
		(Join-Path $FteBasePath "ktx\qconsole.log"),
		(Join-Path $FteBasePath "id1\qconsole.log")
	)

	$existing = @()
	foreach ($candidate in $candidates) {
		if (Test-Path $candidate) {
			$existing += Get-Item $candidate
		}
	}
	if ($existing.Count -gt 0) {
		return ($existing | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
	}

	$found = Get-ChildItem -Path $FteBasePath -Recurse -Filter "qconsole.log" -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
	if ($found) {
		return $found.FullName
	}

	return $candidates[0]
}

function Convert-CsprogsChecksumToken {
	param([string]$Token)

	$value = [UInt64]0
	if ([string]::IsNullOrWhiteSpace($Token)) {
		return $value
	}

	$trimmed = $Token.Trim()
	if ($trimmed.StartsWith("0x", [System.StringComparison]::OrdinalIgnoreCase)) {
		try {
			return [Convert]::ToUInt64($trimmed.Substring(2), 16)
		}
		catch {
			return [UInt64]0
		}
	}

	if ([UInt64]::TryParse($trimmed, [ref]$value)) {
		return $value
	}

	return [UInt64]0
}

function Resolve-ServerCsprogsChecksum {
	param(
		[string]$ServerLogPath,
		[int]$TimeoutSec = 12
	)

	$deadline = (Get-Date).AddSeconds($TimeoutSec)
	while ((Get-Date) -lt $deadline) {
		if (Test-Path $ServerLogPath) {
			$logText = Get-Content -Path $ServerLogPath -Raw -ErrorAction SilentlyContinue
			if ($logText) {
				$patterns = @(
					'\\\*csprogs\\(?<val>0x[0-9a-fA-F]+|\d+)',
					'\*csprogs\((?<val>0x[0-9a-fA-F]+|\d+)\)'
				)
				foreach ($pattern in $patterns) {
					$matches = [regex]::Matches($logText, $pattern)
					if ($matches.Count -gt 0) {
						$token = $matches[$matches.Count - 1].Groups["val"].Value
						$parsed = Convert-CsprogsChecksumToken -Token $token
						if ($parsed -gt 0) {
							return $parsed
						}
					}
				}
			}
		}
		Start-Sleep -Milliseconds 250
	}

	return [UInt64]0
}

function Get-CsprogsChecksumFromFile {
	param([string]$FilePath)

	if (-not (Test-Path $FilePath)) {
		return [UInt64]0
	}

	$bytes = [System.IO.File]::ReadAllBytes($FilePath)
	$crc = 0xffff
	foreach ($b in $bytes) {
		$crc = ($crc -bxor (($b -band 0xff) -shl 8)) -band 0xffff
		for ($i = 0; $i -lt 8; $i++) {
			if (($crc -band 0x8000) -ne 0) {
				$crc = (($crc -shl 1) -bxor 0x1021) -band 0xffff
			}
			else {
				$crc = ($crc -shl 1) -band 0xffff
			}
		}
	}

	return [UInt64]($crc -band 0xffff)
}

function Ensure-CsqcVersionAlias {
	param(
		[string]$BasePath,
		[string]$GameDir,
		[UInt64]$Checksum
	)

	if ($Checksum -le 0) {
		return ""
	}

	$src = Join-Path $BasePath "$GameDir\csprogs.dat"
	if (-not (Test-Path $src)) {
		return ""
	}

	$dstDir = Join-Path $BasePath "$GameDir\csprogsvers"
	New-Item -ItemType Directory -Force -Path $dstDir | Out-Null
	$checksumHex = "{0:x}" -f $Checksum
	$dst = Join-Path $dstDir "$checksumHex.dat"
	if (-not (Test-Path $dst)) {
		Copy-Item -Force -Path $src -Destination $dst
	}

	return $dst
}

function Ensure-CsqcVersionAliasFromSource {
	param(
		[string]$SourceCsprogsPath,
		[string]$TargetBasePath,
		[string]$TargetGameDir,
		[UInt64]$Checksum
	)

	if ($Checksum -le 0 -or -not (Test-Path $SourceCsprogsPath)) {
		return ""
	}

	$dstDir = Join-Path $TargetBasePath "$TargetGameDir\csprogsvers"
	New-Item -ItemType Directory -Force -Path $dstDir | Out-Null
	$checksumHex = "{0:x}" -f $Checksum
	$dst = Join-Path $dstDir "$checksumHex.dat"
	if (-not (Test-Path $dst)) {
		Copy-Item -Force -Path $SourceCsprogsPath -Destination $dst
	}

	return $dst
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$serverExe = Join-Path $repoRoot "build-msvc-x64\Debug\ezquake.exe"
$fteExe = "E:\_RE\runtime\qw-phase1\fteqw_win64\fteqw64.exe"
$fteExeDir = Split-Path -Parent $fteExe
$lossProxyScript = Join-Path $repoRoot "tools\phase4\udp_loss_proxy.ps1"
$connectTarget = "$ClientConnectHost`:$Port"
$lossProxyPort = $Port + 500
$lossProxyConnectTarget = "$ClientConnectHost`:$lossProxyPort"

if (-not (Test-Path $serverExe)) {
	throw "Missing server executable: $serverExe"
}
if (-not (Test-Path $fteExe)) {
	throw "Missing FTE client executable: $fteExe"
}
if ($LossPercent -lt 0 -or $LossPercent -gt 100) {
	throw "LossPercent must be between 0 and 100"
}
if ($LossPercent -gt 0 -and -not (Test-Path $lossProxyScript)) {
	throw "Missing loss proxy script: $lossProxyScript"
}

if (Test-Path $OutputDir) {
	Remove-Item -Recurse -Force $OutputDir
}
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$serverLog = Join-Path $OutputDir "server.log"
$fteBase = Join-Path $OutputDir "fte_base"
$fteLog = Join-Path $fteBase "fte\qconsole.log"
$fteCfg = Join-Path $fteBase "ktx\phase2_auto.cfg"
$driverBase = Join-Path $OutputDir "driver_base"
$driverCfg = Join-Path $driverBase "ezquake\phase2_driver_onenter.cfg"
$driverLog = Join-Path $OutputDir "driver_client.log"
$lossProxyLog = Join-Path $OutputDir "loss_proxy_stdout.log"
$lossProxyErr = Join-Path $OutputDir "loss_proxy_stderr.log"
$lossProxyStop = Join-Path $OutputDir "loss_proxy.stop"
$lossProxyStats = Join-Path $OutputDir "loss_proxy_stats.txt"
$serverCsprogsPath = Join-Path $RuntimeBase "ktx\csprogs.dat"
New-Item -ItemType Directory -Force -Path $fteBase | Out-Null

foreach ($d in @("id1", "ktx")) {
	$src = Join-Path $RuntimeBase $d
	if (Test-Path $src) {
		Copy-Item -Recurse -Force $src (Join-Path $fteBase $d)
	}
}
New-Item -ItemType Directory -Force -Path (Join-Path $fteBase "fte") | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $fteCfg) | Out-Null
Get-ChildItem -Path $fteBase -Recurse -Filter "qconsole.log" -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
if (Test-Path $lossProxyStop) {
	Remove-Item -Force $lossProxyStop
}
if (Test-Path $lossProxyStats) {
	Remove-Item -Force $lossProxyStats
}
if (Test-Path $lossProxyLog) {
	Remove-Item -Force $lossProxyLog
}
if (Test-Path $lossProxyErr) {
	Remove-Item -Force $lossProxyErr
}
if ($LossPercent -gt 0 -and $RouteFteThroughLossProxy) {
	$connectTarget = "$ClientConnectHost`:$lossProxyPort"
}

$fteScript = New-Object System.Collections.Generic.List[string]
$fteScript.Add("echo P2_FTE_BOOT")
$fteScript.Add("developer 1")
$fteScript.Add("cl_shownet 2")
$fteScript.Add("name phase2_fte")
$fteScript.Add("echo P2_FTE_PRECONNECT_WAIT")
for ($i = 0; $i -lt 120; $i++) {
	$fteScript.Add("wait")
}
$fteScript.Add("connect $connectTarget")
$fteScript.Add("echo P2_FTE_CONNECT_ISSUED")
for ($i = 0; $i -lt 300; $i++) {
	$fteScript.Add("wait")
}
$fteScript.Add("cmd ready")
$fteScript.Add("echo P2_FTE_READY_ISSUED")
$fteScript.Add("impulse 9")
$fteScript.Add("impulse 7")
$fteScript.Add("echo P2_FTE_LOADOUT_ISSUED")
$fteScript.Add("+attack")
$fteScript.Add("+forward")
$fteScript.Add("+moveleft")
$fteScript | Set-Content -Path $fteCfg -Encoding ascii

if ($SpawnDriverClient) {
	New-Item -ItemType Directory -Force -Path $driverBase | Out-Null
	New-Item -ItemType Directory -Force -Path (Join-Path $driverBase "ezquake") | Out-Null
	foreach ($d in @("id1", "ktx", "qw", "ezquake")) {
		$src = Join-Path $RuntimeBase $d
		if (Test-Path $src) {
			Copy-Item -Recurse -Force $src (Join-Path $driverBase $d)
		}
	}
	$rocketBody = "echo P2_DRIVER_ROCKET;cmd ready;give r 200;give 7 1;impulse 7;+attack;" + ("wait;" * 220) + "-attack;echo P2_DRIVER_ROCKET_DONE"
	("alias on_enter `"" + $rocketBody + "`"") | Set-Content -Path $driverCfg -Encoding ascii
}

$server = $null
$fte = $null
$driver = $null
$lossProxy = $null
$serverReady = $false
$csprogsChecksum = [UInt64]0
$csprogsChecksumSource = "none"
$serverCsprogsAlias = ""
$fteCsprogsAlias = ""
$fteCsprogsAliasId1 = ""
$fteCsprogsAliasFte = ""

try {
	Stop-AllTargets

	$serverArgs = @(
		"-condebug", $serverLog,
		"-cheats",
		"-dedicated",
		"-allowmultiple",
		"-basedir", $RuntimeBase,
		"-game", "ktx",
		"-port", "$Port",
		"+developer", "1",
		"+sv_showdrop", "1",
		"+rcon_password", "phase2",
		"+sv_crypt_rcon", "0",
		"+maxclients", "8",
		"+serverinfo", "matchtag", "phase2",
		"+k_prewar", "1",
		"+sv_progtype", "2",
		"+sv_csqc_progname", "csprogs.dat",
		"+sv_csqc_sized", $(if ($UseSizedCsqc) { "1" } else { "0" }),
		"+sv_antilag", "1",
		"+map", $MapName
	)
	if ($CsqcDebugDumpBytes -gt 0) {
		$serverArgs += @("+sv_csqc_debug_dump", "$CsqcDebugDumpBytes")
	}
	$server = Start-Process -FilePath $serverExe -WorkingDirectory $repoRoot -ArgumentList $serverArgs -PassThru
	$serverReady = Wait-ServerReady -Process $server -ServerLogPath $serverLog -Port $Port -TimeoutSec 180
	if (-not $serverReady) {
		$tail = ""
		if (Test-Path $serverLog) {
			$tail = (Get-Content -Path $serverLog -Tail 12 -ErrorAction SilentlyContinue) -join "`n"
		}
		throw "Server did not reach ready state before FTE launch (missing ready marker or UDP listener on :$Port). tail=`n$tail"
	}
	$csprogsChecksum = Resolve-ServerCsprogsChecksum -ServerLogPath $serverLog -TimeoutSec 20
	if ($csprogsChecksum -gt 0) {
		$csprogsChecksumSource = "server_log"
	}
	else {
		$csprogsChecksum = Get-CsprogsChecksumFromFile -FilePath $serverCsprogsPath
		if ($csprogsChecksum -gt 0) {
			$csprogsChecksumSource = "file_crc16_fallback"
		}
	}
	if ($csprogsChecksum -gt 0) {
		$serverCsprogsAlias = Ensure-CsqcVersionAlias -BasePath $RuntimeBase -GameDir "ktx" -Checksum $csprogsChecksum
		$fteCsprogsAlias = Ensure-CsqcVersionAlias -BasePath $fteBase -GameDir "ktx" -Checksum $csprogsChecksum
		$fteCsprogsSource = Join-Path $fteBase "ktx\csprogs.dat"
		$fteCsprogsAliasId1 = Ensure-CsqcVersionAliasFromSource -SourceCsprogsPath $fteCsprogsSource -TargetBasePath $fteBase -TargetGameDir "id1" -Checksum $csprogsChecksum
		$fteCsprogsAliasFte = Ensure-CsqcVersionAliasFromSource -SourceCsprogsPath $fteCsprogsSource -TargetBasePath $fteBase -TargetGameDir "fte" -Checksum $csprogsChecksum
	}

	if ($LossPercent -gt 0) {
		$lossProxy = Start-Process -FilePath "powershell" -WorkingDirectory $repoRoot -ArgumentList @(
			"-NoProfile",
			"-ExecutionPolicy", "Bypass",
			"-File", $lossProxyScript,
			"-ListenPort", "$lossProxyPort",
			"-ServerHost", "127.0.0.1",
			"-ServerPort", "$Port",
			"-LossPercentClientToServer", "$LossPercent",
			"-LossPercentServerToClient", "$LossPercent",
			"-StopFilePath", $lossProxyStop,
			"-StatsFilePath", $lossProxyStats
		) -RedirectStandardOutput $lossProxyLog -RedirectStandardError $lossProxyErr -PassThru
		Start-Sleep -Milliseconds 800
	}

	$fte = Start-Process -FilePath $fteExe -WorkingDirectory $fteExeDir -ArgumentList @(
		"-condebug",
		"-window",
		"-startwindowed",
		"+vid_fullscreen", "0",
		"-nosound",
		"-noupdate",
		"-nohome",
		"-basedir", $fteBase,
		"-game", "ktx",
		"+developer", "1",
		"+exec", "phase2_auto.cfg"
	) -PassThru

	if ($SpawnDriverClient) {
		$driverConnectTarget = "127.0.0.1:$Port"
		if ($LossPercent -gt 0 -and $RouteDriverThroughLossProxy) {
			$driverConnectTarget = $lossProxyConnectTarget
		}
		$driver = Start-Process -FilePath $serverExe -WorkingDirectory $repoRoot -ArgumentList @(
			"-condebug", $driverLog,
			"-allowmultiple",
			"-window",
			"-startwindowed",
			"+vid_fullscreen", "0",
			"-nosound",
			"-basedir", $driverBase,
			"-game", "ktx",
			"+name", "phase2_driver",
			"+exec", "phase2_driver_onenter.cfg",
			"+connect", $driverConnectTarget
		) -PassThru
	}
	if ($ForceMatchStart) {
		Start-Sleep -Seconds 2
		Send-RconCommand -Address "127.0.0.1" -Port $Port -Password "phase2" -Command "forcestart"
	}
	Start-Sleep -Seconds $DurationSec
}
finally {
	Stop-IfRunning -Process $driver
	Stop-IfRunning -Process $fte
	Stop-LossProxy -Process $lossProxy -StopFile $lossProxyStop
	Stop-IfRunning -Process $server
}

$summary = Join-Path $OutputDir "summary.txt"
$serverLines = @()
$fteLines = @()
$proxyLines = @()
$fteNotConnectedCount = 0
$fteConnectedMarkerCount = 0
$fteServerJoinCount = 0
$fteServerActiveCount = 0
$fteCsqcFailureCount = 0
$fteHostEndGameCount = 0
$fteCsqcRuntimeAbortCount = 0
$fteCsqcLoadFailed = $false
$fteCsqcRuntimeFailed = $false
$fteConnected = $false
if (Test-Path $serverLog) {
	$serverLines = @(Select-String -Path $serverLog -Pattern "csprogs|csqc|CSQC-ACTIVE|CSQC-PROJECTILE|CSQC-SUMMARY|entered the game|phase2_fte|phase2_driver|PEXT|supports|extensions|dropped|Bad user command|status|using protocol extension" -CaseSensitive:$false -ErrorAction SilentlyContinue | ForEach-Object { $_.Line })
	$fteServerJoinCount = @(Select-String -Path $serverLog -Pattern "phase2_fte entered the game" -CaseSensitive:$false -ErrorAction SilentlyContinue).Count
	$fteServerActiveCount = @(Select-String -Path $serverLog -Pattern "CSQC-ACTIVE:\s+name=phase2_fte\b" -CaseSensitive:$false -ErrorAction SilentlyContinue).Count
}
$fteLog = Resolve-FteLogPath -FteBasePath $fteBase
if (Test-Path $fteLog) {
	$fteLines = @(Select-String -Path $fteLog -Pattern "P2_FTE_|csprogs|csqc|connect|connected|extensions|pext|download|phase2_fte|serverinfo|entity|hostname|players|map|protocol|server|svc_" -CaseSensitive:$false -ErrorAction SilentlyContinue | ForEach-Object { $_.Line })
	$fteText = Get-Content -Path $fteLog -Raw
	$fteNotConnectedCount = ([regex]::Matches($fteText, 'Can''t "cmd", not connected')).Count
	$fteConnectedMarkerCount = ([regex]::Matches($fteText, '(?im)(\bconnected!\b|\bconnection:\b|Serverdata packet received|\bConnected to [^\r\n]+)')).Count
	$fteCsqcFailureCount = ([regex]::Matches($fteText, '(?im)(Unable to load "csprogsvers/[^"]+"|required, but unable to download|required, but not initialised)')).Count
	$fteHostEndGameCount = ([regex]::Matches($fteText, '(?im)^.*Host_EndGame:.*csprogsvers/.*$')).Count
	$fteCsqcRuntimeAbortCount = ([regex]::Matches($fteText, '(?im)(CSQC_Abort:|Host_EndGame:\s*csqc error)')).Count
}
if (Test-Path $lossProxyStats) {
	$proxyLines = Get-Content -Path $lossProxyStats
}
$fteCsqcLoadFailed = ($fteCsqcFailureCount -gt 0) -or ($fteHostEndGameCount -gt 0)
$fteCsqcRuntimeFailed = $fteCsqcRuntimeAbortCount -gt 0
$fteConnected = ($fteServerJoinCount -gt 0) -or ($fteServerActiveCount -gt 0) -or (($fteNotConnectedCount -eq 0) -and ($fteConnectedMarkerCount -gt 0))
$routeDriverThroughLossProxyValue = 0
if ($RouteDriverThroughLossProxy) {
	$routeDriverThroughLossProxyValue = 1
}
$routeFteThroughLossProxyValue = 0
if ($RouteFteThroughLossProxy) {
	$routeFteThroughLossProxyValue = 1
}

@(
	"output_dir=$OutputDir"
	"server_log=$serverLog"
	"fte_log=$fteLog"
	"loss_percent=$LossPercent"
	"loss_proxy_enabled=$([int]($LossPercent -gt 0))"
	"route_driver_through_loss_proxy=$routeDriverThroughLossProxyValue"
	"route_fte_through_loss_proxy=$routeFteThroughLossProxyValue"
	"loss_proxy_stats=$lossProxyStats"
	"server_ready=$([int]$serverReady)"
	"connect_target=$connectTarget"
	"csprogs_checksum=$csprogsChecksum"
	"csprogs_checksum_hex=0x$("{0:x}" -f $csprogsChecksum)"
	"csprogs_checksum_source=$csprogsChecksumSource"
	"server_csqc_alias=$serverCsprogsAlias"
	"fte_csqc_alias=$fteCsprogsAlias"
	"fte_csqc_alias_id1=$fteCsprogsAliasId1"
	"fte_csqc_alias_fte=$fteCsprogsAliasFte"
	"fte_connected=$([int]$fteConnected)"
	"fte_csqc_load_failed=$([int]$fteCsqcLoadFailed)"
	"fte_csqc_runtime_failed=$([int]$fteCsqcRuntimeFailed)"
	"fte_csqc_failure_hits=$fteCsqcFailureCount"
	"fte_host_endgame_hits=$fteHostEndGameCount"
	"fte_csqc_runtime_abort_hits=$fteCsqcRuntimeAbortCount"
	"fte_not_connected_hits=$fteNotConnectedCount"
	"fte_connected_markers=$fteConnectedMarkerCount"
	"fte_server_join_hits=$fteServerJoinCount"
	"fte_server_active_hits=$fteServerActiveCount"
	"server_match_lines=$($serverLines.Count)"
	"fte_match_lines=$($fteLines.Count)"
	"proxy_match_lines=$($proxyLines.Count)"
	"---server-lines---"
) + $serverLines + @(
	"---proxy-lines---"
) + $proxyLines + @(
	"---fte-lines---"
) + $fteLines | Set-Content -Path $summary -Encoding ascii

Get-Content $summary

if (-not $fteConnected) {
	[Console]::Error.WriteLine("P2 probe hard-fail: FTE never reached connected state (target=$connectTarget, not_connected_hits=$fteNotConnectedCount, connected_markers=$fteConnectedMarkerCount, server_join_hits=$fteServerJoinCount)")
	exit 2
}

if ($fteCsqcLoadFailed) {
	[Console]::Error.WriteLine("P2 probe hard-fail: FTE connected but CSQC failed to load (target=$connectTarget, csqc_failure_hits=$fteCsqcFailureCount, host_endgame_hits=$fteHostEndGameCount)")
	exit 3
}

if ($fteCsqcRuntimeFailed) {
	[Console]::Error.WriteLine("P2 probe hard-fail: FTE connected but CSQC runtime aborted (target=$connectTarget, runtime_abort_hits=$fteCsqcRuntimeAbortCount)")
	exit 4
}
