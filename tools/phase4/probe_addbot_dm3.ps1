$exe = 'e:\Repositories\ezquake-source\build-msvc-x64\Debug\ezquake.exe'
$base = 'E:\_RE\runtime\phase3-interop\qwbase'
$out = 'E:\_RE\runtime\phase4-matrix\probe_addbot_dm3'

New-Item -ItemType Directory -Force -Path $out | Out-Null
$slog = Join-Path $out 'server.log'
$clog = Join-Path $out 'client.log'
$cbase = Join-Path $out 'client_base'

Remove-Item $slog, $clog -ErrorAction SilentlyContinue
if (Test-Path $cbase) {
	Remove-Item -Recurse -Force $cbase
}

New-Item -ItemType Directory -Force -Path $cbase | Out-Null
foreach ($d in @('id1', 'ktx', 'qw', 'ezquake')) {
	$src = Join-Path $base $d
	if (Test-Path $src) {
		Copy-Item -Recurse -Force $src (Join-Path $cbase $d)
	}
}

$cfgDir = Join-Path $cbase 'ezquake'
New-Item -ItemType Directory -Force -Path $cfgDir | Out-Null
$cfgPath = Join-Path $cfgDir 'phase4_onenter_addbot.cfg'
"alias on_enter `"cmd botcmd addbot;wait;wait;cmd botcmd addbot`"" | Set-Content -Path $cfgPath -Encoding ascii

Get-Process ezquake -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 1

$sp = Start-Process -FilePath $exe -ArgumentList "-condebug $slog -dedicated -allowmultiple -basedir $base -game ktx -port 28660 +maxclients 8 +sv_progtype 2 +sv_csqc_progname csprogs.dat +sv_antilag 1 +map dm3 +k_fb_enabled 1" -PassThru
Start-Sleep -Seconds 4
$cp = Start-Process -FilePath $exe -ArgumentList "-condebug $clog -allowmultiple -basedir $cbase -port 28690 -window -startwindowed +vid_fullscreen 0 -nosound +name phase4_human +developer 1 +cl_csqc 1 +exec phase4_onenter_addbot.cfg +connect 127.0.0.1:28660" -PassThru

Start-Sleep -Seconds 48
if (-not $cp.HasExited) { Stop-Process -Id $cp.Id -Force }
if (-not $sp.HasExited) { Stop-Process -Id $sp.Id -Force }
Start-Sleep -Milliseconds 500

Write-Output '---CLIENT LINES---'
Select-String -Path $clog -Pattern 'on_enter|botcmd|bot|entered the game|support|Command not known|Unknown command|Map .*supported' | ForEach-Object { $_.Line }
Write-Output '---SERVER LINES---'
Select-String -Path $slog -Pattern 'bot|entered the game|removed|dropped|frag|killed|bro' | ForEach-Object { $_.Line }
