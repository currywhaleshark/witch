param([ValidateSet('import','test','review')][string]$Phase='test', [string]$Test='automaton_assembly')
$ErrorActionPreference='Stop'
$assemblyRoot=Split-Path -Parent $PSScriptRoot
$assemblyLabel=if($Phase -eq 'test'){$Test}else{$Phase}
$assemblyDir=Join-Path $assemblyRoot ('reports/automaton_assembly_v1/'+$assemblyLabel)
New-Item -ItemType Directory -Force -Path $assemblyDir | Out-Null
$assemblyEngine=Join-Path $assemblyRoot 'reports/combat_motion_v18/portable_godot/Godot_v4.6.2-stable_win64_console.exe'
$assemblyArgs=@('--path',('"{0}"' -f (Join-Path $assemblyRoot 'game')),'--audio-driver','Dummy','--log-file',('"{0}"' -f (Join-Path $assemblyDir 'engine.log')))
if($Phase -eq 'import'){$assemblyArgs+=@('--headless','--editor','--import','--quit')}
elseif($Phase -eq 'review'){$assemblyArgs+=@('--resolution','1280x800','--position','-2000,-2000','--script','res://tests/review_automaton_assembly.gd','--',('"--output={0}"' -f $assemblyDir))}
else{$assemblyArgs+=@('--headless','--script',('res://tests/'+$Test+'.gd'),'--',('"--output={0}"' -f (Join-Path $assemblyDir 'result.json')))}
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
@{exit_code=$assemblyProcess.ExitCode;stderr_empty=![bool]$assemblyStderr;workspace_cache_diagnostic_only=([bool]$assemblyStderr -and !$assemblyRemaining);phase=$Phase;test=$Test} | ConvertTo-Json | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $assemblyDir 'execution.json')
Get-Content -LiteralPath (Join-Path $assemblyDir 'stdout.log') -Encoding UTF8 -Tail 2
if($assemblyProcess.ExitCode -ne 0 -or $assemblyRemaining){throw "Assembly check failed: $assemblyStderr"}
