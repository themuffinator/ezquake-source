param(
    [int]$DurationSeconds = 45
)

$ErrorActionPreference = 'Stop'

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$runtimeRoot = 'E:\_RE\runtime\phase3-interop'
$reportDir = Join-Path $runtimeRoot 'reports'
$clientBase = Join-Path $runtimeRoot 'qwbase'
$qwDir = Join-Path $clientBase 'qw'

$serverExe = 'E:\_RE\runtime\qw-phase1\fteqw_win64\fteqwsv64.exe'
$serverBase = 'E:\_RE\runtime\qw-phase1\fteqw_win64'
$serverArgs = '-basedir "' + $serverBase + '" -game csqctest +sv_port 27501 +sv_csqc_progname csprogs.dat +map start'

$clientExe = 'E:\Repositories\ezquake-source\build-msvc-x64\Debug\ezquake.exe'
$clientArgs = '-basedir "' + $clientBase + '" -window -startwindowed +vid_fullscreen 0 -nosound -condebug +exec phase3_fte_probe.cfg'

$cfgPath = Join-Path $qwDir 'phase3_fte_probe.cfg'
$qconsolePath = Join-Path $qwDir 'qconsole.log'
$snapshotPath = Join-Path $qwDir 'csqc_status_last.txt'

$reportPath = Join-Path $reportDir ("phase3_fte_server_probe_$stamp.txt")
$qconsoleCopy = Join-Path $reportDir ("phase3_fte_qconsole_$stamp.log")
$snapshotCopy = Join-Path $reportDir ("phase3_fte_status_$stamp.txt")

New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
if (Test-Path $qconsolePath) { Remove-Item -Force $qconsolePath }
if (Test-Path $snapshotPath) { Remove-Item -Force $snapshotPath }

$cfgLines = New-Object System.Collections.Generic.List[string]
$cfgLines.Add('developer 1')
$cfgLines.Add('cl_csqc 1')
$cfgLines.Add('cl_csqc_allow_unsized_nonktx 1')
$cfgLines.Add('cl_shownet 2')
$cfgLines.Add('connect 127.0.0.1:27501')
for ($i = 0; $i -lt 180; $i++) {
    $cfgLines.Add('wait')
}
$cfgLines.Add('cl_csqc_status')
for ($i = 0; $i -lt 220; $i++) {
    $cfgLines.Add('wait')
}
$cfgLines.Add('cl_csqc_status')
$cfgLines | Set-Content -Path $cfgPath -Encoding ascii

$server = Start-Process -FilePath $serverExe -ArgumentList $serverArgs -WorkingDirectory $serverBase -PassThru
Start-Sleep -Seconds 3
$client = Start-Process -FilePath $clientExe -ArgumentList $clientArgs -WorkingDirectory 'E:\Repositories\ezquake-source' -PassThru

$welcomeSeen = $false
$enableSentSeen = $false
$deadline = (Get-Date).AddSeconds($DurationSeconds)

while ((Get-Date) -lt $deadline) {
    $client.Refresh()
    if ($client.HasExited) {
        break
    }

    if (Test-Path $qconsolePath) {
        $tail = Get-Content -Path $qconsolePath -Tail 200 -ErrorAction SilentlyContinue
        if ($tail -match 'Welcome to csqctest!') {
            $welcomeSeen = $true
        }
        if ($tail -match 'CSQC: sending server command "enablecsqc"') {
            $enableSentSeen = $true
        }
    }

    Start-Sleep -Milliseconds 500
}

$client.Refresh()
if (-not $client.HasExited) {
    Stop-Process -Id $client.Id -Force
    Start-Sleep -Milliseconds 400
}

$server.Refresh()
if (-not $server.HasExited) {
    Stop-Process -Id $server.Id -Force
    Start-Sleep -Milliseconds 400
}

if (Test-Path $qconsolePath) {
    Copy-Item -Path $qconsolePath -Destination $qconsoleCopy -Force
}

if (Test-Path $snapshotPath) {
    Copy-Item -Path $snapshotPath -Destination $snapshotCopy -Force
}

$svcCsqc = 0
$svcCsqcSized = 0
$svcCgame = 0
$svcCgameSized = 0
$messages70 = ''
$transportEnabled = $false
$pextEnabled = $false
$worldLoaded = $false
$csprogsName = "none"
$csprogsChecksum = [uint32]0
$csprogsSize = 0
$csprogsLocal = $false
$csprogsCached = $false
$parseEntityPackets = 0
$parseUpdates = 0
$parseRemoves = 0
$dropsTotal = 0
$dropsUnknownSized = 0
$dropsUnknownUnsized = 0
$dropsUnsizedCgame = 0
if (Test-Path $snapshotCopy) {
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
        if ($line -match '^messages csqcentities=(\d+) csqcentities_sized=(\d+) cgamepacket=(\d+) cgamepacket_sized=(\d+)') {
            $svcCsqc = [int]$Matches[1]
            $svcCsqcSized = [int]$Matches[2]
            $svcCgame = [int]$Matches[3]
            $svcCgameSized = [int]$Matches[4]
        }
        elseif ($line -match '^messages70_100(.*)$') {
            $messages70 = $Matches[1].Trim()
        }
        elseif ($line -match '^parse entity_packets=(\d+) sized_entity_packets=(\d+) updates=(\d+) removes=(\d+) cgame_packets=(\d+)') {
            $parseEntityPackets = [int]$Matches[1]
            $parseUpdates = [int]$Matches[3]
            $parseRemoves = [int]$Matches[4]
        }
        elseif ($line -match '^drops total=(\d+) unknown_sized=(\d+) unknown_unsized=(\d+) unsized_cgamepacket=(\d+)') {
            $dropsTotal = [int]$Matches[1]
            $dropsUnknownSized = [int]$Matches[2]
            $dropsUnknownUnsized = [int]$Matches[3]
            $dropsUnsizedCgame = [int]$Matches[4]
        }
    }
}

$qconsoleText = ''
if (Test-Path $qconsoleCopy) {
    $qconsoleText = Get-Content -Path $qconsoleCopy -Raw
    if ($qconsoleText -match 'Welcome to csqctest!') {
        $welcomeSeen = $true
    }
    if ($qconsoleText -match 'CSQC: sending server command \"enablecsqc\"') {
        $enableSentSeen = $true
    }
}

$shownetCsqcCount = ([regex]::Matches($qconsoleText, 'svc_fte_csqcentities')).Count
$shownetCsqcSizedCount = ([regex]::Matches($qconsoleText, 'svc_fte_csqcentities_sized')).Count
$shownetCgameCount = ([regex]::Matches($qconsoleText, 'svc_fte_cgamepacket')).Count
$shownetCgameSizedCount = ([regex]::Matches($qconsoleText, 'svc_fte_cgamepacket_sized')).Count
$shownetUpdateEntitiesCount = ([regex]::Matches($qconsoleText, 'svc_fte_updateentities')).Count
$disconnectLoopHits = ([regex]::Matches($qconsoleText, 'Connection lost or aborted')).Count
$fatalPattern = 'Host_Error|CL_ParseServerMessage: Bad server message|SZ_GetSpace: overflow|svc_bad'
$fatalHits = ([regex]::Matches($qconsoleText, $fatalPattern)).Count

$messageFlowOk = ($svcCsqc + $svcCsqcSized + $shownetCsqcCount + $shownetCsqcSizedCount) -gt 0
$parseFlowOk = ($parseUpdates -gt 0) -or (($shownetCsqcCount -gt 0) -and ($fatalHits -eq 0))
$enableSignalOk = $enableSentSeen -or $welcomeSeen
$stabilityOk = ($disconnectLoopHits -lt 3) -and ($fatalHits -eq 0)
$transportOk = ($transportEnabled -and $pextEnabled -and $worldLoaded) -or ($shownetCsqcCount -gt 0)
$csprogsOk = (($csprogsName -ieq "csprogs.dat") -and ($csprogsLocal -or $csprogsCached) -and ($csprogsChecksum -gt 0)) -or ($shownetCsqcCount -gt 0)
$reportPass = (Test-Path $qconsoleCopy) -and $transportOk -and $csprogsOk -and $messageFlowOk -and $parseFlowOk -and $enableSignalOk -and $stabilityOk

@(
    "timestamp=$stamp",
    "duration_seconds=$DurationSeconds",
    "report_pass=$reportPass",
    "server_pid=$($server.Id)",
    "client_pid=$($client.Id)",
    "welcome_seen=$welcomeSeen",
    "enable_sent_seen=$enableSentSeen",
    "snapshot_exists=$([bool](Test-Path $snapshotCopy))",
    "snapshot_path=$snapshotCopy",
    "transport_enabled=$transportEnabled",
    "pext_enabled=$pextEnabled",
    "world_loaded=$worldLoaded",
    "csprogs_name=$csprogsName",
    "csprogs_checksum=$csprogsChecksum",
    "csprogs_size=$csprogsSize",
    "csprogs_local=$csprogsLocal",
    "csprogs_cached=$csprogsCached",
    "qconsole_exists=$([bool](Test-Path $qconsoleCopy))",
    "qconsole_path=$qconsoleCopy",
    "report_path=$reportPath",
    "snapshot_messages csqcentities=$svcCsqc csqcentities_sized=$svcCsqcSized cgamepacket=$svcCgame cgamepacket_sized=$svcCgameSized",
    "snapshot_parse entity_packets=$parseEntityPackets updates=$parseUpdates removes=$parseRemoves",
    "snapshot_drops total=$dropsTotal unknown_sized=$dropsUnknownSized unknown_unsized=$dropsUnknownUnsized unsized_cgamepacket=$dropsUnsizedCgame",
    "snapshot_messages70_100=$messages70",
    "shownet_hits updateentities=$shownetUpdateEntitiesCount csqcentities=$shownetCsqcCount csqcentities_sized=$shownetCsqcSizedCount cgamepacket=$shownetCgameCount cgamepacket_sized=$shownetCgameSizedCount",
    "disconnect_loop_hits=$disconnectLoopHits",
    "fatal_hits=$fatalHits"
) | Set-Content -Path $reportPath -Encoding ascii

Get-Content -Path $reportPath

if (-not $reportPass) {
    exit 1
}
