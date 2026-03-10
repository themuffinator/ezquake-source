$exe = 'e:\Repositories\ezquake-source\build-msvc-x64\Debug\ezquake.exe'
$base = 'E:\_RE\runtime\phase3-interop\qwbase'
$out = 'E:\_RE\runtime\phase4-matrix\probe_bots'
New-Item -ItemType Directory -Force -Path $out | Out-Null
$slog = Join-Path $out 'server.log'
$clog = Join-Path $out 'client.log'
Remove-Item $slog,$clog -ErrorAction SilentlyContinue
$sp = Start-Process -FilePath $exe -ArgumentList "-condebug $slog -dedicated -allowmultiple -basedir $base -game ktx -port 28655 +maxclients 8 +sv_progtype 2 +sv_csqc_progname csprogs.dat +sv_antilag 1 +k_fb_enabled 1 +k_fb_autoadd_limit 2 +k_fb_auto_delay 1 +map dm2" -PassThru
Start-Sleep -Seconds 4
$cp = Start-Process -FilePath $exe -ArgumentList "-condebug $clog -allowmultiple -basedir $base -window -startwindowed +vid_fullscreen 0 -nosound +name phase4_human +developer 1 +cl_csqc 1 +connect 127.0.0.1:28655" -PassThru
Start-Sleep -Seconds 24
if(-not $cp.HasExited){Stop-Process -Id $cp.Id -Force}
if(-not $sp.HasExited){Stop-Process -Id $sp.Id -Force}
Start-Sleep -Milliseconds 500
Write-Output '---SERVER BOT LINES---'
Select-String -Path $slog -Pattern 'bot|entered the game|dropped|removed|Frog|frogbot|phase4_human' | ForEach-Object { $_.Line }
Write-Output '---SERVER TAIL---'
Get-Content $slog -Tail 60
