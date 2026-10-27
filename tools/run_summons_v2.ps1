param([string]$Phase='runtime', [string]$Test='summons_v2')
$ErrorActionPreference='Stop'
$actorRoot=Split-Path -Parent $PSScriptRoot
$actorReport=Join-Path $actorRoot 'reports/summons_v2'
$actorEngine=Join-Path $actorRoot 'reports/combat_motion_v18/portable_godot/Godot_v4.6.2-stable_win64_console.exe'
$actorGame=Join-Path $actorRoot 'game'
$actorLabel=if($Phase -eq 'test'){$Test}else{$Phase}
$actorDir=Join-Path $actorReport $actorLabel
New-Item -ItemType Directory -Force -Path $actorDir | Out-Null
$actorArgs=@('--path',('"{0}"' -f $actorGame),'--audio-driver','Dummy','--log-file',('"{0}"' -f (Join-Path $actorDir 'engine.log')))
if($Phase -eq 'import') {$actorArgs+=@('--headless','--editor','--import','--quit')}
elseif($Phase -eq 'review') {$actorArgs+=@('--resolution','1280x800','--position','-2000,-2000','--script','res://tests/review_summons_v2.gd','--',('"--output={0}"' -f $actorDir))}
else {
    if($Phase -eq 'test'){$actorArgs+=@('--headless')}else{$actorArgs+=@('--resolution','1280x800','--position','-2000,-2000')}
    $actorArgs+=@('--script',('res://tests/'+$Test+'.gd'),'--',('"--output={0}"' -f (Join-Path $actorDir 'result.json')))
    if($Test -eq 'grades_hits'){$actorArgs+=('"--test-log-dir={0}"' -f (Join-Path $actorDir 'grade_logs'))}
}
$actorProcess=Start-Process -FilePath $actorEngine -ArgumentList $actorArgs -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $actorDir 'stdout.log') -RedirectStandardError (Join-Path $actorDir 'stderr.log')
while(-not $actorProcess.WaitForExit(1000)) {
    $actorErrors=Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $actorDir 'stderr.log') -ErrorAction SilentlyContinue
    if($actorErrors -match 'SCRIPT ERROR|Parse Error|Assertion failed') {Stop-Process -Id $actorProcess.Id;throw $actorErrors}
}
$actorProcess.Refresh()
$actorStdout=Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $actorDir 'stdout.log')
$actorStderr=Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $actorDir 'stderr.log')
$actorRemaining=''
if($actorStderr) {$actorRemaining=([string]$actorStderr).Replace("`r",'').Trim()}
$actorCache="ERROR: Can't create shader cache folder, no shader caching will happen: user://`n   at: RasterizerGLES3 (drivers/gles3/rasterizer_gles3.cpp:335)"
$actorProfiler="ERROR: Could not open 'user://' directory: 'user://'.`n   at: _get_and_create_snapshot_storage_dir (modules/objectdb_profiler/editor/objectdb_profiler_panel.cpp:154)"
$actorRemaining=$actorRemaining.Replace($actorCache,'').Replace($actorProfiler,'').Trim()
@{exit_code=$actorProcess.ExitCode;stderr_empty=![bool]$actorStderr;workspace_cache_diagnostic_only=([bool]$actorStderr -and !$actorRemaining);phase=$Phase;test=$Test} | ConvertTo-Json | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $actorDir 'execution.json')
Write-Output $actorStdout
if($actorProcess.ExitCode -ne 0 -or $actorRemaining) {throw "Actor check failed: $actorStderr"}

