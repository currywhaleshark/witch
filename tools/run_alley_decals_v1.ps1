param([ValidateSet('import','review','map_nav')][string]$Phase='review')
$ErrorActionPreference='Stop'
$decalRoot=Split-Path -Parent $PSScriptRoot
$decalDir=Join-Path $decalRoot ('reports/alley_decals_v1/'+$Phase)
$decalEngine=Join-Path $decalRoot 'reports/combat_motion_v18/portable_godot/Godot_v4.6.2-stable_win64_console.exe'
New-Item -ItemType Directory -Force -Path $decalDir | Out-Null
$decalArgs=@('--path',('"{0}"' -f (Join-Path $decalRoot 'game')),'--audio-driver','Dummy','--log-file',('"{0}"' -f (Join-Path $decalDir 'engine.log')))
if($Phase -eq 'import'){$decalArgs+=@('--headless','--editor','--import','--quit')}
elseif($Phase -eq 'map_nav'){$decalArgs+=@('--headless','--script','res://tests/map_nav.gd')}
else{$decalArgs+=@('--resolution','1280x800','--position','-2000,-2000','--script','res://tests/review_alley_decals.gd','--',('"--output={0}"' -f $decalDir))}
$decalProcess=Start-Process -FilePath $decalEngine -ArgumentList $decalArgs -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $decalDir 'stdout.log') -RedirectStandardError (Join-Path $decalDir 'stderr.log')
$null=$decalProcess.Handle
$decalDeadline=[DateTime]::UtcNow.AddMinutes(10)
while(-not $decalProcess.WaitForExit(1000)){
    $decalErrors=Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $decalDir 'stderr.log') -ErrorAction SilentlyContinue
    if($decalErrors -match 'SCRIPT ERROR|Parse Error|Assertion failed' -or [DateTime]::UtcNow -gt $decalDeadline){Stop-Process -Id $decalProcess.Id;throw "Engine aborted: $decalErrors"}
}
$decalProcess.Refresh()
$decalStderr=Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $decalDir 'stderr.log')
$decalRemaining=''
if($decalStderr){$decalRemaining=([string]$decalStderr).Replace("`r",'').Trim()}
$decalCache="ERROR: Can't create shader cache folder, no shader caching will happen: user://`n   at: RasterizerGLES3 (drivers/gles3/rasterizer_gles3.cpp:335)"
$decalProfiler="ERROR: Could not open 'user://' directory: 'user://'.`n   at: _get_and_create_snapshot_storage_dir (modules/objectdb_profiler/editor/objectdb_profiler_panel.cpp:154)"
$decalRemaining=$decalRemaining.Replace($decalCache,'').Replace($decalProfiler,'').Trim()
@{exit_code=$decalProcess.ExitCode;stderr_empty=![bool]$decalStderr;workspace_cache_diagnostic_only=([bool]$decalStderr -and !$decalRemaining);phase=$Phase} | ConvertTo-Json | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $decalDir 'execution.json')
if($Phase -eq 'map_nav'){Copy-Item -LiteralPath (Join-Path $decalRoot 'reports/godot_map_report.json') -Destination (Join-Path $decalDir 'result.json')}
Get-Content -LiteralPath (Join-Path $decalDir 'stdout.log') -Encoding UTF8 -Tail 8
if($decalProcess.ExitCode -ne 0 -or $decalRemaining){throw "Decal check failed: $decalStderr"}
