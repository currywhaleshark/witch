param([ValidateSet('import','test','gpu_test','review','review_light')][string]$Phase='test',[string]$Test='transformation_v27')
$ErrorActionPreference='Stop'
$v27Root=Split-Path -Parent $PSScriptRoot
$v27Label=if($Phase -in @('test','gpu_test')){$Test}else{$Phase}
$v27Output=Join-Path $v27Root ('reports/transformation_v27/'+$v27Label)
New-Item -ItemType Directory -Force -Path $v27Output|Out-Null
$v27Engine=Join-Path $v27Root 'reports/combat_motion_v18/portable_godot/Godot_v4.6.2-stable_win64_console.exe'
$v27Args=@('--path',('"{0}"' -f (Join-Path $v27Root 'game')),'--audio-driver','Dummy','--log-file',('"{0}"' -f (Join-Path $v27Output 'engine.log')))
if($Phase -eq 'import'){$v27Args+=@('--headless','--editor','--import','--quit')}
elseif($Phase -in @('review','review_light','gpu_test')){
 $v27Review=if($Phase -eq 'gpu_test'){'res://tests/'+$Test+'.gd'}elseif($Phase -eq 'review_light'){'res://tests/review_transformation_v27_light.gd'}else{'res://tests/review_transformation_v27.gd'}
 $v27Args+=@('--resolution','1280x800','--position','-2000,-2000','--script',$v27Review,'--',('"--output={0}"' -f $v27Output))
}
else{$v27Args+=@('--headless','--script',('res://tests/'+$Test+'.gd'),'--',('"--output={0}"' -f (Join-Path $v27Output 'result.json')))}
$v27Paths=@('game/scripts/player_visual.gd','game/scripts/modular_character_runtime.gd','game/scripts/field_entry_transformation.gd','game/scripts/hair_motion.gd','game/scripts/outfit_reveal.gd','game/shaders/outfit_reveal.gdshader','game/scripts/arena.gd','game/data/trial.json','game/assets/characters/player/transformation_v26/combat_transform_entry_v26.glb','game/assets/characters/player/transformation_v25/outfit_transformed_v4.glb','game/assets/characters/player/transformation_v27/hair_semilong_v27.glb','game/assets/characters/player/transformation_v27/hair_contract.json')
$v27Before=@{}
foreach($path in $v27Paths){$v27Before[$path]=(Get-FileHash -LiteralPath (Join-Path $v27Root $path)).Hash}
$v27Before|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $v27Output 'inputs_before.json') -Encoding UTF8
$v27Process=Start-Process -FilePath $v27Engine -ArgumentList $v27Args -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $v27Output 'stdout.log') -RedirectStandardError (Join-Path $v27Output 'stderr.log')
$null=$v27Process.Handle
$v27Deadline=[DateTime]::UtcNow.AddMinutes(7)
while(-not $v27Process.WaitForExit(1000)){
 $v27Errors=Get-Content -LiteralPath (Join-Path $v27Output 'stderr.log') -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
 if($v27Errors -match 'SCRIPT ERROR|Parse Error|Assertion failed' -or [DateTime]::UtcNow -gt $v27Deadline){Stop-Process -Id $v27Process.Id;throw "Verification failed: $v27Errors"}
}
$v27Process.Refresh()
$v27Changed=@($v27Paths|Where-Object {$v27Before[$_] -ne (Get-FileHash -LiteralPath (Join-Path $v27Root $_)).Hash})
$v27Err=Get-Content -LiteralPath (Join-Path $v27Output 'stderr.log') -Raw -Encoding UTF8
@{exit_code=$v27Process.ExitCode;changed_inputs=$v27Changed;stderr=$v27Err}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $v27Output 'execution.json') -Encoding UTF8
Get-Content -LiteralPath (Join-Path $v27Output 'stdout.log') -Encoding UTF8 -Tail 4
if($v27Err){Write-Output $v27Err}
if($v27Process.ExitCode -ne 0 -or $v27Changed.Count){throw 'Verification failed'}
