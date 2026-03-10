$exe = 'e:\Repositories\ezquake-source\build-msvc-x64\Debug\ezquake.exe'
$base = 'E:\_RE\runtime\phase3-interop\qwbase'
$out = 'E:\_RE\runtime\phase4-matrix\probe_botcmd'
New-Item -ItemType Directory -Force -Path $out | Out-Null
$slog = Join-Path $out 'server.log'
$clog = Join-Path $out 'client.log'
Remove-Item $slog,$clog -ErrorAction SilentlyContinue
$sp = Start-Process -FilePath $exe -ArgumentList "-condebug $slog -dedicated -allowmultiple -basedir $base -game ktx -port 28656 +maxclients 8 +sv_progtype 2 +sv_csqc_progname csprogs.dat +sv_antilag 1 +map dm2" -PassThru
Start-Sleep -Seconds 4
$cp = Start-Process -FilePath $exe -ArgumentList "-condebug $clog -allowmultiple -basedir $base -window -startwindowed +vid_fullscreen 0 -nosound +name phase4_human +developer 1 +cl_csqc 1 +connect 127.0.0.1:28656 +botcmd enable +botcmd addbot" -PassThru
Start-Sleep -Seconds 32
if(-not $cp.HasExited){Stop-Process -Id $cp.Id -Force}
if(-not $sp.HasExited){Stop-Process -Id $sp.Id -Force}
Start-Sleep -Milliseconds 500
Write-Output '---CLIENT BOTCMD LINES---'
Select-String -Path $clog -Pattern 'botcmd|Bots|bot|entered the game|map support|admin|known|disabled|enable' | ForEach-Object { $_.Line }
Write-Output '---SERVER BOT LINES---'
Select-String -Path $slog -Pattern 'bot|entered the game|Frog|frogbot|Client .* removed|dropped' | ForEach-Object { $_.Line }
