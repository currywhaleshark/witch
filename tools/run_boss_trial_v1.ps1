param([ValidateSet('import','boss_art','boss','map_nav','combat_actors','summons_v2','review','core_probe')][string]$Phase='review')
$ErrorActionPreference='Stop'
$bossRoot=Split-Path -Parent $PSScriptRoot
$bossDir=Join-Path $bossRoot ('reports/boss_trial_v1/'+$Phase)
$bossEngine=Join-Path $bossRoot 'reports/combat_motion_v18/portable_godot/Godot_v4.6.2-stable_win64_console.exe'
New-Item -ItemType Directory -Force -Path $bossDir | Out-Null
$bossArgs=@('--path',('"{0}"' -f (Join-Path $bossRoot 'game')),'--audio-driver','Dummy','--log-file',('"{0}"' -f (Join-Path $bossDir 'engine.log')))
if($Phase -eq 'import'){$bossArgs+=@('--headless','--editor','--import','--quit')}
elseif($Phase -eq 'review'){$bossArgs+=@('--resolution','1280x800','--position','-2000,-2000','--script','res://tests/review_boss_trial_v1.gd','--',('"--output={0}"' -f $bossDir))}
elseif($Phase -eq 'core_probe'){$bossArgs+=@('--resolution','800x800','--position','-2000,-2000','--script','res://tests/inspect_boss_core.gd')}
else{$bossArgs+=@('--headless','--script',('res://tests/'+$Phase+'.gd'),'--',('"--output={0}"' -f (Join-Path $bossDir 'result.json')))}
$bossProcess=Start-Process -FilePath $bossEngine -ArgumentList $bossArgs -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $bossDir 'stdout.log') -RedirectStandardError (Join-Path $bossDir 'stderr.log')
$null=$bossProcess.Handle
$bossDeadline=[DateTime]::UtcNow.AddMinutes(10)
while(-not $bossProcess.WaitForExit(1000)){
    $bossErrors=Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $bossDir 'stderr.log') -ErrorAction SilentlyContinue
    if($bossErrors -match 'SCRIPT ERROR|Parse Error|Assertion failed' -or [DateTime]::UtcNow -gt $bossDeadline){Stop-Process -Id $bossProcess.Id;throw "Engine aborted: $bossErrors"}
}
$bossProcess.Refresh()
$bossStderr=Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $bossDir 'stderr.log')
$bossRemaining=''
if($bossStderr){$bossRemaining=([string]$bossStderr).Replace("`r",'').Trim()}
$bossCache="ERROR: Can't create shader cache folder, no shader caching will happen: user://`n   at: RasterizerGLES3 (drivers/gles3/rasterizer_gles3.cpp:335)"
$bossProfiler="ERROR: Could not open 'user://' directory: 'user://'.`n   at: _get_and_create_snapshot_storage_dir (modules/objectdb_profiler/editor/objectdb_profiler_panel.cpp:154)"
$bossRemaining=$bossRemaining.Replace($bossCache,'').Replace($bossProfiler,'').Trim()
@{exit_code=$bossProcess.ExitCode;stderr_empty=![bool]$bossStderr;workspace_cache_diagnostic_only=([bool]$bossStderr -and !$bossRemaining);phase=$Phase} | ConvertTo-Json | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $bossDir 'execution.json')
if($Phase -eq 'map_nav'){Copy-Item -LiteralPath (Join-Path $bossRoot 'reports/godot_map_report.json') -Destination (Join-Path $bossDir 'result.json')}
if($Phase -eq 'boss'){Copy-Item -LiteralPath (Join-Path $bossRoot 'reports/godot_boss_report.json') -Destination (Join-Path $bossDir 'result.json')}
Get-Content -LiteralPath (Join-Path $bossDir 'stdout.log') -Encoding UTF8 -Tail 3
if($bossProcess.ExitCode -ne 0 -or $bossRemaining){throw "Boss check failed: $bossStderr"}
