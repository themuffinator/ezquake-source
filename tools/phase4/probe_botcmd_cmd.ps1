$exe = 'e:\Repositories\ezquake-source\build-msvc-x64\Debug\ezquake.exe'
$base = 'E:\_RE\runtime\phase3-interop\qwbase'
$out = 'E:\_RE\runtime\phase4-matrix\probe_botcmd_cmd'
New-Item -ItemType Directory -Force -Path $out | Out-Null
$slog = Join-Path $out 'server.log'
$clog = Join-Path $out 'client.log'
Remove-Item $slog,$clog -ErrorAction SilentlyContinue
Get-Process ezquake -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 1
$sp = Start-Process -FilePath $exe -ArgumentList "-condebug $slog -dedicated -allowmultiple -basedir $base -game ktx -port 28657 +maxclients 8 +sv_progtype 2 +sv_csqc_progname csprogs.dat +sv_antilag 1 +map dm2" -PassThru
Start-Sleep -Seconds 4
$cp = Start-Process -FilePath $exe -ArgumentList "-condebug $clog -allowmultiple -basedir $base -port 28687 -window -startwindowed +vid_fullscreen 0 -nosound +name phase4_human +developer 1 +cl_csqc 1 +connect 127.0.0.1:28657 +cmd botcmd enable +cmd botcmd addbot" -PassThru
Start-Sleep -Seconds 34
if(-not $cp.HasExited){Stop-Process -Id $cp.Id -Force}
if(-not $sp.HasExited){Stop-Process -Id $sp.Id -Force}
Start-Sleep -Milliseconds 500
Write-Output '---CLIENT LINES---'
Select-String -Path $clog -Pattern 'botcmd|Bots|bot|entered the game|Unknown command|admin|support|enable|cmd botcmd' | ForEach-Object { $_.Line }
Write-Output '---SERVER LINES---'
Select-String -Path $slog -Pattern 'bot|entered the game|Frog|frogbot|removed|dropped|You must|enable|support' | ForEach-Object { $_.Line }
