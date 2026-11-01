param([string]$Phase='test',[string]$Test='transformation_v27')
$ErrorActionPreference='Stop'
$v28Root=Split-Path -Parent $PSScriptRoot
$v28Label=if($Phase -eq 'test'){$Test}else{$Phase}
$v28Output=Join-Path $v28Root ('reports/model_refinement_v28/'+$v28Label)
New-Item -ItemType Directory -Force -Path $v28Output|Out-Null
$v28Engine=Join-Path $v28Root 'reports/combat_motion_v18/portable_godot/Godot_v4.6.2-stable_win64_console.exe'
$v28Args=@('--path',('"{0}"' -f (Join-Path $v28Root 'game')),'--audio-driver','Dummy','--log-file',('"{0}"' -f (Join-Path $v28Output 'engine.log')))
if($Phase -eq 'import'){$v28Args+=@('--headless','--editor','--import','--quit')}
elseif($Phase -eq 'review'){$v28Args+=@('--resolution','1280x800','--position','-2000,-2000','--script','res://tests/review_model_refinement_v28.gd','--',('"--output={0}"' -f $v28Output))}
else{
 $v28Result=if($Test -eq 'player_visual'){$v28Output}else{Join-Path $v28Output 'result.json'}
 $v28Args+=@('--headless','--script',('res://tests/'+$Test+'.gd'),'--',('"--output={0}"' -f $v28Result))
}
$v28Paths=@('game/scripts/player_visual.gd','game/scripts/modular_character_runtime.gd','game/scripts/field_entry_transformation.gd','game/scripts/hair_motion.gd','game/scripts/outfit_reveal.gd','game/scripts/arena.gd','game/data/trial.json')+@(Get-ChildItem -LiteralPath (Join-Path $v28Root 'game/assets/characters/player/model_refinement_v28') -Filter '*.glb'|ForEach-Object{'game/assets/characters/player/model_refinement_v28/'+$_.Name})
$v28Before=@{}
foreach($path in $v28Paths){$v28Before[$path]=(Get-FileHash -LiteralPath (Join-Path $v28Root $path)).Hash}
$v28Before|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $v28Output 'inputs_before.json') -Encoding UTF8
$v28Process=Start-Process -FilePath $v28Engine -ArgumentList $v28Args -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $v28Output 'stdout.log') -RedirectStandardError (Join-Path $v28Output 'stderr.log')
$null=$v28Process.Handle
$v28Deadline=[DateTime]::UtcNow.AddMinutes(7)
while(-not $v28Process.WaitForExit(1000)){
 $v28Errors=Get-Content -LiteralPath (Join-Path $v28Output 'stderr.log') -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
 if($v28Errors -match 'SCRIPT ERROR|Parse Error|Assertion failed' -or [DateTime]::UtcNow -gt $v28Deadline){Stop-Process -Id $v28Process.Id;throw "Verification failed: $v28Errors"}
}
$v28Process.Refresh()
$v28Changed=@($v28Paths|Where-Object {$v28Before[$_] -ne (Get-FileHash -LiteralPath (Join-Path $v28Root $_)).Hash})
$v28Err=Get-Content -LiteralPath (Join-Path $v28Output 'stderr.log') -Raw -Encoding UTF8
@{exit_code=$v28Process.ExitCode;changed_inputs=$v28Changed;stderr=$v28Err}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $v28Output 'execution.json') -Encoding UTF8
Get-Content -LiteralPath (Join-Path $v28Output 'stdout.log') -Encoding UTF8 -Tail 3
if($v28Err){Write-Output $v28Err}
if($v28Process.ExitCode -ne 0 -or $v28Changed.Count){throw 'Verification failed'}
