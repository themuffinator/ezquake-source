param(
    [int]$DurationSeconds = 45,
    [int]$Port = 27521,
    [string]$MapName = "dm2",
    [string]$RuntimeBase = "E:\_RE\runtime\phase3-interop\qwbase",
    [switch]$ForceEnableCmd
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
        Start-Sleep -Milliseconds 400
    }
}

function Stop-AllTargets {
    $targets = Get-Process -Name "ezquake", "fteqwsv64" -ErrorAction SilentlyContinue
    if ($null -ne $targets) {
        $targets | Stop-Process -Force
        Start-Sleep -Seconds 1
    }
}

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$runtimeRoot = "E:\_RE\runtime\phase3-interop"
$reportDir = Join-Path $runtimeRoot "reports"
$qwDir = Join-Path $RuntimeBase "qw"

$serverExe = "E:\_RE\runtime\qw-phase1\fteqw_win64\fteqwsv64.exe"
$serverExeDir = Split-Path -Parent $serverExe
$clientExe = "E:\Repositories\ezquake-source\build-msvc-x64\Debug\ezquake.exe"
$clientExeDir = "E:\Repositories\ezquake-source"

if (-not (Test-Path $serverExe)) {
    throw "Missing FTE server executable: $serverExe"
}
if (-not (Test-Path $clientExe)) {
    throw "Missing ezQuake executable: $clientExe"
}
if (-not (Test-Path (Join-Path $RuntimeBase "id1\pak0.pak"))) {
    throw "Runtime base is missing id1 pak0.pak: $RuntimeBase"
}
if (-not (Test-Path (Join-Path $RuntimeBase "ktx\csprogs.dat"))) {
    throw "Runtime base is missing KTX csprogs.dat: $RuntimeBase"
}

$cfgPath = Join-Path $qwDir "phase3_fte_ktx_probe.cfg"
$onEnterCfgPath = Join-Path $RuntimeBase "ezquake\phase3_fte_ktx_onenter.cfg"
$qconsolePath = Join-Path $qwDir "qconsole.log"
$snapshotPath = Join-Path $qwDir "csqc_status_last.txt"

$reportPath = Join-Path $reportDir ("phase3_fte_ktx_probe_$stamp.txt")
$serverLogPath = Join-Path $reportDir ("phase3_fte_ktx_server_$stamp.log")
$serverStdoutPath = Join-Path $reportDir ("phase3_fte_ktx_server_stdout_$stamp.log")
$serverStderrPath = Join-Path $reportDir ("phase3_fte_ktx_server_stderr_$stamp.log")
$qconsoleCopy = Join-Path $reportDir ("phase3_fte_ktx_qconsole_$stamp.log")
$snapshotCopy = Join-Path $reportDir ("phase3_fte_ktx_status_$stamp.txt")

New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
New-Item -ItemType Directory -Force -Path $qwDir | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $onEnterCfgPath) | Out-Null
if (Test-Path $qconsolePath) { Remove-Item -Force $qconsolePath }
if (Test-Path $snapshotPath) { Remove-Item -Force $snapshotPath }
if (Test-Path $serverLogPath) { Remove-Item -Force $serverLogPath }
if (Test-Path $serverStdoutPath) { Remove-Item -Force $serverStdoutPath }
if (Test-Path $serverStderrPath) { Remove-Item -Force $serverStderrPath }

$waitChain = "wait;" * 220
("alias on_enter ""echo P3_KTX_ON_ENTER;cmd ready;impulse 9;impulse 7;+attack;+forward;+moveleft;{0}-attack;-forward;-moveleft;echo P3_KTX_ACTIONS_DONE""" -f $waitChain) | Set-Content -Path $onEnterCfgPath -Encoding ascii

$cfgLines = New-Object System.Collections.Generic.List[string]
$cfgLines.Add("developer 1")
$cfgLines.Add("cl_csqc 1")
$cfgLines.Add("cl_csqc_force_enablecmd_ktx " + ($(if ($ForceEnableCmd) { "1" } else { "0" })))
$cfgLines.Add("cl_shownet 2")
$cfgLines.Add("noskins 1")
$cfgLines.Add("name phase3_ktx_probe")
$cfgLines.Add("exec phase3_fte_ktx_onenter.cfg")
$cfgLines.Add("connect 127.0.0.1:$Port")
for ($i = 0; $i -lt 220; $i++) {
    $cfgLines.Add("wait")
}
$cfgLines.Add("echo P3_KTX_READY")
$cfgLines.Add("cmd ready")
$cfgLines.Add("cl_csqc_status")
for ($i = 0; $i -lt 140; $i++) {
    $cfgLines.Add("wait")
}
$cfgLines.Add("cl_csqc_status")
for ($i = 0; $i -lt 220; $i++) {
    $cfgLines.Add("wait")
}
$cfgLines.Add("cl_csqc_status")
$cfgLines | Set-Content -Path $cfgPath -Encoding ascii

$server = $null
$client = $null

$enableSentSeen = $false
$serverExitedEarly = $false
$deadline = (Get-Date).AddSeconds($DurationSeconds)

try {
    Stop-AllTargets

    $serverArgs = @(
        "-condebug", $serverLogPath,
        "-basedir", $RuntimeBase,
        "-game", "ktx",
        "+developer", "1",
        "+sv_public", "0",
        "+sv_port", "$Port",
        "+sv_csqc_progname", "csprogs.dat",
        "+map", $MapName
    )
    $server = Start-Process -FilePath $serverExe -ArgumentList $serverArgs -WorkingDirectory $serverExeDir -RedirectStandardOutput $serverStdoutPath -RedirectStandardError $serverStderrPath -PassThru
    Start-Sleep -Seconds 3

    $clientArgs = @(
        "-basedir", $RuntimeBase,
        "-window",
        "-startwindowed",
        "+vid_fullscreen", "0",
        "-nosound",
        "-nohome",
        "-condebug",
        "+exec", "phase3_fte_ktx_probe.cfg"
    )
    $client = Start-Process -FilePath $clientExe -ArgumentList $clientArgs -WorkingDirectory $clientExeDir -PassThru

    while ((Get-Date) -lt $deadline) {
        $server.Refresh()
        if ($server.HasExited) {
            $serverExitedEarly = $true
        }

        $client.Refresh()
        if ($client.HasExited) {
            break
        }

        if (Test-Path $qconsolePath) {
            $tail = Get-Content -Path $qconsolePath -Tail 200 -ErrorAction SilentlyContinue
            if ($tail -match 'CSQC: sending server command "enablecsqc"') {
                $enableSentSeen = $true
            }
        }

        Start-Sleep -Milliseconds 500
    }
}
finally {
    Stop-IfRunning -Process $client
    Stop-IfRunning -Process $server
}

if (Test-Path $qconsolePath) {
    Copy-Item -Path $qconsolePath -Destination $qconsoleCopy -Force
}
if (Test-Path $snapshotPath) {
    Copy-Item -Path $snapshotPath -Destination $snapshotCopy -Force
}

$snapshotExists = Test-Path $snapshotCopy
$qconsoleExists = Test-Path $qconsoleCopy
$serverLogExists = Test-Path $serverLogPath
$serverStdoutExists = Test-Path $serverStdoutPath
$serverStderrExists = Test-Path $serverStderrPath

$transportEnabled = $false
$pextEnabled = $false
$worldLoaded = $false
$csprogsName = "none"
$csprogsChecksum = [uint32]0
$csprogsSize = 0
$csprogsLocal = $false
$csprogsCached = $false
$parseEntityPackets = 0
$parseSizedEntityPackets = 0
$parseUpdates = 0
$parseRemoves = 0
$parseCgamePackets = 0
$msgCsqc = 0
$msgCsqcSized = 0
$msgCgame = 0
$msgCgameSized = 0
$msgHistogram = ""

if ($snapshotExists) {
    $statusLines = Get-Content -Path $snapshotCopy
    foreach ($line in $statusLines) {
        if ($line -match '^transport=(\w+) cvar=\d+ pext=(\w+) world=(\w+)') {
            $transportEnabled = ($Matches[1] -eq "enabled")
            $pextEnabled = ($Matches[2] -eq "yes")
            $worldLoaded = ($Matches[3] -eq "yes")
        }
        elseif ($line -match '^csprogs name=(\S+) checksum=(\d+) size=(-?\d+) local=(\w+) cached=(\w+)') {
            $csprogsName = $Matches[1]
            $csprogsChecksum = [uint32]$Matches[2]
            $csprogsSize = [int]$Matches[3]
            $csprogsLocal = ($Matches[4] -eq "yes")
            $csprogsCached = ($Matches[5] -eq "yes")
        }
        elseif ($line -match '^parse entity_packets=(\d+) sized_entity_packets=(\d+) updates=(\d+) removes=(\d+) cgame_packets=(\d+)') {
            $parseEntityPackets = [int]$Matches[1]
            $parseSizedEntityPackets = [int]$Matches[2]
            $parseUpdates = [int]$Matches[3]
            $parseRemoves = [int]$Matches[4]
            $parseCgamePackets = [int]$Matches[5]
        }
        elseif ($line -match '^messages csqcentities=(\d+) csqcentities_sized=(\d+) cgamepacket=(\d+) cgamepacket_sized=(\d+)') {
            $msgCsqc = [int]$Matches[1]
            $msgCsqcSized = [int]$Matches[2]
            $msgCgame = [int]$Matches[3]
            $msgCgameSized = [int]$Matches[4]
        }
        elseif ($line -match '^messages70_100(.*)$') {
            $msgHistogram = $Matches[1].Trim()
        }
    }
}

$qconsoleText = ""
$serverText = ""
if ($qconsoleExists) {
    $qconsoleText = Get-Content -Path $qconsoleCopy -Raw
    if ($qconsoleText -match 'CSQC: sending server command \"enablecsqc\"') {
        $enableSentSeen = $true
    }
}
if ($serverLogExists) {
    $serverText = Get-Content -Path $serverLogPath -Raw
}
if ($serverStdoutExists) {
    $serverText += "`n" + (Get-Content -Path $serverStdoutPath -Raw)
}
if ($serverStderrExists) {
    $serverText += "`n" + (Get-Content -Path $serverStderrPath -Raw)
}

$shownetUpdateEntities = ([regex]::Matches($qconsoleText, 'svc_fte_updateentities')).Count
$shownetCsqc = ([regex]::Matches($qconsoleText, 'svc_fte_csqcentities(?!_sized)')).Count
$shownetCsqcSized = ([regex]::Matches($qconsoleText, 'svc_fte_csqcentities_sized')).Count
$shownetCgame = ([regex]::Matches($qconsoleText, 'svc_fte_cgamepacket(?!_sized)')).Count
$shownetCgameSized = ([regex]::Matches($qconsoleText, 'svc_fte_cgamepacket_sized')).Count
$ktxMarkerHits = ([regex]::Matches($qconsoleText, 'ktxver|ktxmode|\\ktx\\|/ktx/')).Count + ([regex]::Matches($serverText, 'gamedir.*ktx|\\bktx\\b')).Count

$fatalPattern = 'Host_Error|CL_ParseServerMessage: Bad server message|SZ_GetSpace: overflow|svc_bad'
$fatalClientHits = ([regex]::Matches($qconsoleText, $fatalPattern)).Count
$fatalServerHits = ([regex]::Matches($serverText, $fatalPattern)).Count
$fatalHits = $fatalClientHits + $fatalServerHits
$disconnectLoopHits = ([regex]::Matches($qconsoleText, 'Connection lost or aborted')).Count

$transportOk = $transportEnabled -and $pextEnabled -and $worldLoaded
$csprogsOk = ($csprogsName -ieq "csprogs.dat") -and ($csprogsLocal -or $csprogsCached) -and ($csprogsChecksum -gt 0)
$messageFlowOk = ($msgCsqc + $msgCsqcSized + $shownetCsqc + $shownetCsqcSized) -gt 0
$updateFlowOk = ($shownetUpdateEntities -gt 0) -or ($msgHistogram -match '(^| )86=')
$parseFlowOk = $parseUpdates -gt 0
$serverEvidenceOk = $serverLogExists -or $serverStdoutExists -or $serverStderrExists
$sessionStable = ($disconnectLoopHits -lt 3)
$enableSignalOk = $enableSentSeen -or (-not $ForceEnableCmd)
$bootstrapPass = $snapshotExists -and $qconsoleExists -and $enableSignalOk -and $transportOk -and $csprogsOk -and ($ktxMarkerHits -gt 0) -and ($fatalHits -eq 0)
$streamingPass = $bootstrapPass -and $serverEvidenceOk -and $messageFlowOk -and $updateFlowOk -and $parseFlowOk -and $sessionStable
$forceEnableCmdValue = if ($ForceEnableCmd) { 1 } else { 0 }

@(
    "timestamp=$stamp",
    "duration_seconds=$DurationSeconds",
    "force_enablecmd=$forceEnableCmdValue",
    "server_game=ktx",
    "server_port=$Port",
    "map=$MapName",
    "runtime_base=$RuntimeBase",
    "report_path=$reportPath",
    "report_pass=$streamingPass",
    "milestone2_bootstrap_pass=$bootstrapPass",
    "streaming_pass=$streamingPass",
    "session_stable=$sessionStable",
    "server_exited_early=$serverExitedEarly",
    "server_log_exists=$serverLogExists",
    "server_log_path=$serverLogPath",
    "server_stdout_exists=$serverStdoutExists",
    "server_stdout_path=$serverStdoutPath",
    "server_stderr_exists=$serverStderrExists",
    "server_stderr_path=$serverStderrPath",
    "qconsole_exists=$qconsoleExists",
    "qconsole_path=$qconsoleCopy",
    "snapshot_exists=$snapshotExists",
    "snapshot_path=$snapshotCopy",
    "enable_sent_seen=$enableSentSeen",
    "transport_enabled=$transportEnabled",
    "pext_enabled=$pextEnabled",
    "world_loaded=$worldLoaded",
    "csprogs_name=$csprogsName",
    "csprogs_checksum=$csprogsChecksum",
    "csprogs_size=$csprogsSize",
    "csprogs_local=$csprogsLocal",
    "csprogs_cached=$csprogsCached",
    "parse_entity_packets=$parseEntityPackets",
    "parse_sized_entity_packets=$parseSizedEntityPackets",
    "parse_updates=$parseUpdates",
    "parse_removes=$parseRemoves",
    "parse_cgame_packets=$parseCgamePackets",
    "messages_csqcentities=$msgCsqc",
    "messages_csqcentities_sized=$msgCsqcSized",
    "messages_cgamepacket=$msgCgame",
    "messages_cgamepacket_sized=$msgCgameSized",
    "messages70_100=$msgHistogram",
    "shownet_updateentities=$shownetUpdateEntities",
    "shownet_csqcentities=$shownetCsqc",
    "shownet_csqcentities_sized=$shownetCsqcSized",
    "shownet_cgamepacket=$shownetCgame",
    "shownet_cgamepacket_sized=$shownetCgameSized",
    "ktx_marker_hits=$ktxMarkerHits",
    "disconnect_loop_hits=$disconnectLoopHits",
    "fatal_hits=$fatalHits",
    "fatal_client_hits=$fatalClientHits",
    "fatal_server_hits=$fatalServerHits"
) | Set-Content -Path $reportPath -Encoding ascii

Get-Content -Path $reportPath
