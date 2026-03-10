$exe = 'e:\Repositories\ezquake-source\build-msvc-x64\Debug\ezquake.exe'
$base = 'E:\_RE\runtime\phase3-interop\qwbase'
$out = 'E:\_RE\runtime\phase4-matrix\probe_servercfg_bots_dm3'

New-Item -ItemType Directory -Force -Path $out | Out-Null
$serverBase = Join-Path $out 'server_base'
$clientBase = Join-Path $out 'client_base'
$slog = Join-Path $out 'server.log'
$clog = Join-Path $out 'client.log'

Remove-Item $slog, $clog -ErrorAction SilentlyContinue
foreach ($b in @($serverBase, $clientBase)) {
	if (Test-Path $b) {
		Remove-Item -Recurse -Force $b
	}
	New-Item -ItemType Directory -Force -Path $b | Out-Null
	foreach ($d in @('id1', 'ktx', 'qw', 'ezquake')) {
		$src = Join-Path $base $d
		if (Test-Path $src) {
			Copy-Item -Recurse -Force $src (Join-Path $b $d)
		}
	}
}

$ktxDir = Join-Path $serverBase 'ktx'
New-Item -ItemType Directory -Force -Path $ktxDir | Out-Null
$serverCfg = Join-Path $ktxDir 'server.cfg'
@'
k_fb_enabled 1
k_fb_autoadd_limit 3
k_fb_auto_delay 1
'@ | Set-Content -Path $serverCfg -Encoding ascii

Get-Process ezquake -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 1

$sp = Start-Process -FilePath $exe -ArgumentList "-condebug $slog -dedicated -allowmultiple -basedir $serverBase -game ktx -port 28663 +maxclients 8 +sv_progtype 2 +sv_csqc_progname csprogs.dat +sv_antilag 1 +map dm3" -PassThru
Start-Sleep -Seconds 4
$cp = Start-Process -FilePath $exe -ArgumentList "-condebug $clog -allowmultiple -basedir $clientBase -port 28693 -window -startwindowed +vid_fullscreen 0 -nosound +name phase4_human +developer 1 +cl_csqc 1 +connect 127.0.0.1:28663" -PassThru

Start-Sleep -Seconds 65
if (-not $cp.HasExited) { Stop-Process -Id $cp.Id -Force }
if (-not $sp.HasExited) { Stop-Process -Id $sp.Id -Force }
Start-Sleep -Milliseconds 500

Write-Output '---SERVER LINES---'
Select-String -Path $slog -Pattern 'server.cfg|bot|entered the game|removed|dropped|Map .*supported|not supported|skill' | ForEach-Object { $_.Line }
Write-Output '---CLIENT LINES---'
Select-String -Path $clog -Pattern 'entered the game|on_enter|bot|Host_Error|Connection lost' | ForEach-Object { $_.Line }
