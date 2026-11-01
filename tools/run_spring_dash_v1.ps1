param([ValidateSet('import','test','review')][string]$Phase='test',[string]$Test='spring_plate_v1',[string]$ReportDir='reports/spring_dash_v1',[string]$ReviewScript='review_spring_plate_v1')
$ErrorActionPreference='Stop'
$springRoot=Split-Path -Parent $PSScriptRoot
$springLabel=if($Phase -eq 'test'){$Test}else{$Phase}
$springDir=Join-Path $springRoot ($ReportDir+'/'+$springLabel)
New-Item -ItemType Directory -Force -Path $springDir | Out-Null
$springEngine=Join-Path $springRoot 'reports/combat_motion_v18/portable_godot/Godot_v4.6.2-stable_win64_console.exe'
$springArgs=@('--path',('"{0}"' -f (Join-Path $springRoot 'game')),'--audio-driver','Dummy','--log-file',('"{0}"' -f (Join-Path $springDir 'engine.log')))
if($Phase -eq 'import'){$springArgs+=@('--headless','--editor','--import','--quit')}
elseif($Phase -eq 'review'){$springArgs+=@('--resolution','1280x800','--position','-2000,-2000','--script',('res://tests/'+$ReviewScript+'.gd'),'--',('"--output={0}"' -f $springDir))}
else{
 $springOutput=if($Test -in @('player_visual','player_motion_v18')){$springDir}else{Join-Path $springDir 'result.json'}
 $springArgs+=@('--headless','--script',('res://tests/'+$Test+'.gd'),'--',('"--output={0}"' -f $springOutput))
}
$springFiles=@('game/scripts/arena.gd','game/scripts/spring_plate.gd','game/scripts/summon_assembly.gd','game/scripts/player_visual.gd','game/scripts/combat_rules.gd','game/scripts/field_map.gd','game/data/trial.json','game/audio/mechanical_impact.wav','game/assets/props/spring_dash_v1/spring_plate.glb','game/assets/props/spring_dash_v1/parts.json')
$springFiles+=if($Phase -eq 'review'){@('game/tests/'+$ReviewScript+'.gd','game/tests/review_spring_plate_v1.gd','game/tests/review_staff_visual.gd')}elseif($Phase -eq 'test'){@('game/tests/'+$Test+'.gd')}else{@()}
$springFiles=@($springFiles|Where-Object {Test-Path -LiteralPath (Join-Path $springRoot $_)}|Select-Object -Unique)
$springBefore=@{}
foreach($springFile in $springFiles){
 $springCopy=Join-Path $springDir ('input_sources/'+$springFile)
 New-Item -ItemType Directory -Force -Path (Split-Path -Parent $springCopy)|Out-Null
 Copy-Item -LiteralPath (Join-Path $springRoot $springFile) -Destination $springCopy
 $springBefore[$springFile]=(Get-FileHash -LiteralPath $springCopy -Algorithm SHA256).Hash.ToLowerInvariant()
}
$springBefore|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $springDir 'inputs_before.json') -Encoding UTF8
$springProcess=Start-Process -FilePath $springEngine -ArgumentList $springArgs -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $springDir 'stdout.log') -RedirectStandardError (Join-Path $springDir 'stderr.log')
$null=$springProcess.Handle
$springDeadline=[DateTime]::UtcNow.AddMinutes(6)
while(-not $springProcess.WaitForExit(1000)){
 $springErrors=Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $springDir 'stderr.log') -ErrorAction SilentlyContinue
 if($springErrors -match 'SCRIPT ERROR|Parse Error|Assertion failed' -or [DateTime]::UtcNow -gt $springDeadline){Stop-Process -Id $springProcess.Id;throw "Spring check aborted: $springErrors"}
}
$springProcess.Refresh()
$springStderr=Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $springDir 'stderr.log')
$springRemaining=if($springStderr){([string]$springStderr).Replace("`r",'').Trim()}else{''}
$springCache="ERROR: Can't create shader cache folder, no shader caching will happen: user://`n   at: RasterizerGLES3 (drivers/gles3/rasterizer_gles3.cpp:335)"
$springProfiler="ERROR: Could not open 'user://' directory: 'user://'.`n   at: _get_and_create_snapshot_storage_dir (modules/objectdb_profiler/editor/objectdb_profiler_panel.cpp:154)"
$springRemaining=$springRemaining.Replace($springCache,'').Replace($springProfiler,'').Trim()
$springAfter=@{}
foreach($springFile in $springFiles){$springAfter[$springFile]=(Get-FileHash -LiteralPath (Join-Path $springRoot $springFile) -Algorithm SHA256).Hash.ToLowerInvariant()}
$springChanged=@($springFiles|Where-Object {$springBefore[$_] -ne $springAfter[$_]})
$springAfter|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $springDir 'inputs_after.json') -Encoding UTF8
@{exit_code=$springProcess.ExitCode;stderr_empty=![bool]$springStderr;workspace_cache_diagnostic_only=([bool]$springStderr -and !$springRemaining);phase=$Phase;test=$Test;changed_inputs=$springChanged}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $springDir 'execution.json') -Encoding UTF8
Get-Content -LiteralPath (Join-Path $springDir 'stdout.log') -Encoding UTF8 -Tail 2
if($springProcess.ExitCode -ne 0 -or $springRemaining){throw "Spring check failed: $springStderr"}
if($springChanged.Count){throw "Inputs changed during check: $springChanged"}
if($Phase -eq 'test'){
 $springLegacy=@{loadout_dash='loadout_dash';hit_block='hit_block';tool_switch='tool';hold_input='hold'}
 if($springLegacy.ContainsKey($Test)){Copy-Item -LiteralPath (Join-Path $springRoot ('reports/godot_'+$springLegacy[$Test]+'_report.json')) -Destination (Join-Path $springDir 'result.json')}
 if($Test -eq 'player_visual'){Copy-Item -LiteralPath (Join-Path $springDir 'player_visual_validation.json') -Destination (Join-Path $springDir 'result.json')}
 if($Test -eq 'player_motion_v18'){Copy-Item -LiteralPath (Join-Path $springDir 'variant_validation.json') -Destination (Join-Path $springDir 'result.json')}
}
