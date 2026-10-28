param([ValidateSet('import','test','review')][string]$Phase='test', [string]$Test='shotgun_cast')
$ErrorActionPreference='Stop'
$assemblyRoot=Split-Path -Parent $PSScriptRoot
$assemblyLabel=if($Phase -eq 'test'){$Test}else{$Phase}
$assemblyDir=Join-Path $assemblyRoot ('reports/shotgun_cast_v1/'+$assemblyLabel)
New-Item -ItemType Directory -Force -Path $assemblyDir | Out-Null
$assemblyEngine=Join-Path $assemblyRoot 'reports/combat_motion_v18/portable_godot/Godot_v4.6.2-stable_win64_console.exe'
$assemblyArgs=@('--path',('"{0}"' -f (Join-Path $assemblyRoot 'game')),'--audio-driver','Dummy','--log-file',('"{0}"' -f (Join-Path $assemblyDir 'engine.log')))
if($Phase -eq 'import'){$assemblyArgs+=@('--headless','--editor','--import','--quit')}
elseif($Phase -eq 'review'){$assemblyArgs+=@('--resolution','1280x800','--position','-2000,-2000','--script','res://tests/review_shotgun_cast.gd','--',('"--output={0}"' -f $assemblyDir))}
else{$assemblyArgs+=@('--headless','--script',('res://tests/'+$Test+'.gd'),'--',('"--output={0}"' -f (Join-Path $assemblyDir 'result.json')))}
if($Test -eq 'grades_hits'){$assemblyArgs+=('"--test-log-dir={0}"' -f (Join-Path $assemblyDir 'a5_logs'))}
$assemblyInputFiles=@('game/scripts/arena.gd','game/scripts/summon_assembly.gd','game/scripts/automaton_assembly.gd','game/scripts/turret_assembly.gd','game/scripts/actor_visual.gd','game/scripts/player_visual.gd','game/scripts/combat_rules.gd','game/data/trial.json',('game/tests/'+$Test+'.gd'),'game/tests/review_shotgun_cast.gd','game/scripts/shotgun_cast.gd','game/scripts/shotgun_geometry.gd') | Select-Object -Unique
if($Phase -ne 'review'){$assemblyInputFiles=@($assemblyInputFiles | Where-Object {$_ -ne 'game/tests/review_shotgun_cast.gd'})}
$assemblyInputFiles=@($assemblyInputFiles | Where-Object {Test-Path -LiteralPath (Join-Path $assemblyRoot $_)})
$assemblyBefore=@{}
foreach($assemblyInput in $assemblyInputFiles){
 $shotSnapshot=Join-Path $assemblyDir ('input_sources/'+$assemblyInput)
 New-Item -ItemType Directory -Force -Path (Split-Path -Parent $shotSnapshot) | Out-Null
 Copy-Item -LiteralPath (Join-Path $assemblyRoot $assemblyInput) -Destination $shotSnapshot
 $assemblyBefore[$assemblyInput]=(Get-FileHash -Algorithm SHA256 -LiteralPath $shotSnapshot).Hash.ToLowerInvariant()
}
$assemblyBefore | ConvertTo-Json | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $assemblyDir 'inputs_before.json')
$assemblyProcess=Start-Process -FilePath $assemblyEngine -ArgumentList $assemblyArgs -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $assemblyDir 'stdout.log') -RedirectStandardError (Join-Path $assemblyDir 'stderr.log')
$null=$assemblyProcess.Handle
$assemblyDeadline=[DateTime]::UtcNow.AddMinutes(8)
while(-not $assemblyProcess.WaitForExit(1000)){
    $assemblyErrors=Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $assemblyDir 'stderr.log') -ErrorAction SilentlyContinue
    if($assemblyErrors -match 'SCRIPT ERROR|Parse Error|Assertion failed' -or [DateTime]::UtcNow -gt $assemblyDeadline){Stop-Process -Id $assemblyProcess.Id;throw "Engine aborted: $assemblyErrors"}
}
$assemblyProcess.Refresh()
$assemblyStderr=Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $assemblyDir 'stderr.log')
$assemblyRemaining=if($assemblyStderr){([string]$assemblyStderr).Replace("`r",'').Trim()}else{''}
$assemblyCache="ERROR: Can't create shader cache folder, no shader caching will happen: user://`n   at: RasterizerGLES3 (drivers/gles3/rasterizer_gles3.cpp:335)"
$assemblyProfiler="ERROR: Could not open 'user://' directory: 'user://'.`n   at: _get_and_create_snapshot_storage_dir (modules/objectdb_profiler/editor/objectdb_profiler_panel.cpp:154)"
$assemblyRemaining=$assemblyRemaining.Replace($assemblyCache,'').Replace($assemblyProfiler,'').Trim()
$assemblyAfter=@{}
foreach($assemblyInput in $assemblyInputFiles){$assemblyAfter[$assemblyInput]=(Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $assemblyRoot $assemblyInput)).Hash.ToLowerInvariant()}
$assemblyAfter | ConvertTo-Json | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $assemblyDir 'inputs_after.json')
$assemblyChanged=@($assemblyInputFiles | Where-Object {$assemblyBefore[$_] -ne $assemblyAfter[$_]})
@{exit_code=$assemblyProcess.ExitCode;stderr_empty=![bool]$assemblyStderr;workspace_cache_diagnostic_only=([bool]$assemblyStderr -and !$assemblyRemaining);phase=$Phase;test=$Test;changed_inputs=$assemblyChanged} | ConvertTo-Json | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $assemblyDir 'execution.json')
Get-Content -LiteralPath (Join-Path $assemblyDir 'stdout.log') -Encoding UTF8 -Tail 2
if($assemblyProcess.ExitCode -ne 0 -or $assemblyRemaining){throw "Assembly check failed: $assemblyStderr"}
if($assemblyChanged.Count){throw "Inputs changed during validation: $assemblyChanged"}

if($Phase -eq 'test') {
 $shotLegacy=@{hit_block='hit_block';hold_input='hold';grades_hits='grades';approach_cast='approach';tool_switch='tool'}
 if($shotLegacy.ContainsKey($Test)) {Copy-Item -LiteralPath (Join-Path $assemblyRoot ('reports/godot_'+$shotLegacy[$Test]+'_report.json')) -Destination (Join-Path $assemblyDir 'result.json')}
}
