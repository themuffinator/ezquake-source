$ErrorActionPreference='Stop'
$exe='E:\Repositories\ezquake-source\build-msvc-x64\Debug\ezquake.exe'
$base='E:\_RE\runtime\phase3-interop\qwbase'
$out='E:\_RE\runtime\phase4-matrix\probe_lifecycle_manual3'
$port=28684

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

$cfg1=Join-Path $c1base 'ezquake\onenter1.cfg'
$cfg2=Join-Path $c2base 'ezquake\onenter2.cfg'
New-Item -ItemType Directory -Force -Path (Split-Path $cfg1) | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path $cfg2) | Out-Null
$on1='echo C1_MODE;cmd ffa;wait;wait;echo C1_READY;cmd ready'
$on2='echo C2_MODE;cmd ffa;wait;wait;echo C2_READY;cmd ready'
('alias on_enter "' + $on1 + '"') | Set-Content -Path $cfg1 -Encoding ascii
('alias on_enter "' + $on2 + '"') | Set-Content -Path $cfg2 -Encoding ascii

$svArgs="-condebug $svlog -dedicated -allowmultiple -basedir $base -game ktx -port $port +set timelimit 1 +set fraglimit 0 +set k_overtime 1 +set k_exttime 1 +set k_count 3 +maxclients 8 +sv_progtype 2 +sv_csqc_progname csprogs.dat +sv_antilag 1 +map dm2"
$sv=Start-Process -FilePath $exe -ArgumentList $svArgs -PassThru
Start-Sleep -Seconds 3

$c1Args="-condebug $c1log -allowmultiple -basedir $c1base -game ktx -port 28784 -window -startwindowed -nosound +vid_fullscreen 0 +name lf3_client1 +cl_csqc 1 +developer 1 +exec onenter1.cfg +connect 127.0.0.1:$port"
$c2Args="-condebug $c2log -allowmultiple -basedir $c2base -game ktx -port 28785 -window -startwindowed -nosound +vid_fullscreen 0 +name lf3_client2 +cl_csqc 1 +developer 1 +exec onenter2.cfg +connect 127.0.0.1:$port"
$c1=Start-Process -FilePath $exe -ArgumentList $c1Args -PassThru
Start-Sleep -Milliseconds 900
$c2=Start-Process -FilePath $exe -ArgumentList $c2Args -PassThru

Start-Sleep -Seconds 26

foreach($p in @($c2,$c1,$sv)){ if($p -and -not $p.HasExited){ Stop-Process -Id $p.Id -Force } }
Start-Sleep -Milliseconds 500

"--- SERVER ---"
rg -n -i "entered the game|get rid of|all players ready|timer started|countdown|match has begun|status|min left|overtime" $svlog
"--- CLIENT1 ---"
rg -n -i "C1_|fullserverinfo|status\\|countdown|min left|all players ready|timer started|match has begun|get rid of" $c1log
"--- CLIENT2 ---"
rg -n -i "C2_|fullserverinfo|status\\|countdown|min left|all players ready|timer started|match has begun|get rid of" $c2log
