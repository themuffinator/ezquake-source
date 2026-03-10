$ErrorActionPreference='Stop'
$exe='E:\Repositories\ezquake-source\build-msvc-x64\Debug\ezquake.exe'
$base='E:\_RE\runtime\phase3-interop\qwbase'
$out='E:\_RE\runtime\phase4-matrix\probe_lifecycle_manual1'
$port=28680

Get-Process ezquake -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 1
if(Test-Path $out){Remove-Item -Recurse -Force $out}
New-Item -ItemType Directory -Force -Path $out | Out-Null

function Copy-Base([string]$dst){
  New-Item -ItemType Directory -Force -Path $dst | Out-Null
  foreach($d in @('id1','ktx','qw','ezquake')){ $src=Join-Path $base $d; if(Test-Path $src){ Copy-Item -Recurse -Force $src (Join-Path $dst $d) } }
  foreach($f in @('installed.lst','identity.pfx')){ $src=Join-Path $base $f; if(Test-Path $src){ Copy-Item -Force $src (Join-Path $dst $f) } }
}

$svlog=Join-Path $out 'server.log'
$c1log=Join-Path $out 'client1.log'
$c2log=Join-Path $out 'client2.log'
$c1base=Join-Path $out 'client1_base'
$c2base=Join-Path $out 'client2_base'
Copy-Base $c1base
Copy-Base $c2base

$w95=('wait;'*95)
$w100=('wait;'*100)
$w20=('wait;'*20)
$cfg1=Join-Path $c1base 'ezquake\onenter1.cfg'
$cfg2=Join-Path $c2base 'ezquake\onenter2.cfg'
New-Item -ItemType Directory -Force -Path (Split-Path $cfg1) | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path $cfg2) | Out-Null
$on1 = 'echo LFC1_READY;ready;echo LFC1_WAITING;' + $w95 + 'echo LFC1_BREAK;break;' + $w20 + 'scores'
$on2 = 'echo LFC2_READY;ready;echo LFC2_WAITING;' + $w100 + 'echo LFC2_BREAK;break;' + $w20 + 'scores'
('alias on_enter "' + $on1 + '"') | Set-Content -Path $cfg1 -Encoding ascii
('alias on_enter "' + $on2 + '"') | Set-Content -Path $cfg2 -Encoding ascii

$svArgs="-condebug $svlog -dedicated -allowmultiple -basedir $base -game ktx -port $port +maxclients 8 +sv_progtype 2 +sv_csqc_progname csprogs.dat +sv_antilag 1 +map dm2 +timelimit 1 +fraglimit 0 +k_overtime 1 +k_exttime 1 +k_count 3"
$sv=Start-Process -FilePath $exe -ArgumentList $svArgs -PassThru
Start-Sleep -Seconds 3

$c1Args="-condebug $c1log -allowmultiple -basedir $c1base -game ktx -port 28780 -window -startwindowed -nosound +vid_fullscreen 0 +name lf_client1 +cl_csqc 1 +developer 1 +shownet 1 +exec onenter1.cfg +connect 127.0.0.1:$port"
$c2Args="-condebug $c2log -allowmultiple -basedir $c2base -game ktx -port 28781 -window -startwindowed -nosound +vid_fullscreen 0 +name lf_client2 +cl_csqc 1 +developer 1 +shownet 1 +exec onenter2.cfg +connect 127.0.0.1:$port"
$c1=Start-Process -FilePath $exe -ArgumentList $c1Args -PassThru
Start-Sleep -Milliseconds 800
$c2=Start-Process -FilePath $exe -ArgumentList $c2Args -PassThru

Start-Sleep -Seconds 140

foreach($p in @($c2,$c1,$sv)){ if($p -and -not $p.HasExited){ Stop-Process -Id $p.Id -Force } }
Start-Sleep -Milliseconds 500

"--- SERVER MARKERS ---"
Select-String -Path $svlog -Pattern 'status|Countdown|match has begun|min left|time over|overtime|The match is over|Match stopped by majority vote|intermission|next map|changelevel|LFC' -SimpleMatch -ErrorAction SilentlyContinue | ForEach-Object {$_.Line}
"--- CLIENT1 MARKERS ---"
Select-String -Path $c1log -Pattern 'LFC1_|fullserverinfo|status\\|Countdown|min left|overtime|Intermission|svc_intermission|Match stopped by majority vote|scores' -ErrorAction SilentlyContinue | ForEach-Object {$_.Line}
"--- CLIENT2 MARKERS ---"
Select-String -Path $c2log -Pattern 'LFC2_|fullserverinfo|status\\|Countdown|min left|overtime|Intermission|svc_intermission|Match stopped by majority vote|scores' -ErrorAction SilentlyContinue | ForEach-Object {$_.Line}
