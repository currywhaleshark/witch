param([ValidateSet('import','parity','gameplay','variants','hands')][string]$Phase='import', [switch]$Prepared, [string]$GodotPath='C:/Users/yurib/Downloads/Godot_v4.6.2-stable_win64.exe/Godot_v4.6.2-stable_win64_console.exe')
$ErrorActionPreference='Stop'
$motionRoot=Split-Path -Parent $PSScriptRoot
$motionReport=Join-Path $motionRoot 'reports/run_arm_v21/integration'
$motionGame=Join-Path $motionRoot 'game'
# Godot's documented self-contained mode keeps editor settings and caches in
# this task's writable workspace, without modifying the installed application.
$portableDir=Join-Path $motionRoot 'reports/combat_motion_v18/portable_godot'
New-Item -ItemType Directory -Force -Path $portableDir | Out-Null
$originalConsole=$GodotPath
$originalGui=$GodotPath.Replace('_console.exe','.exe')
foreach ($binary in @($originalConsole,$originalGui)) {
    $copy=Join-Path $portableDir (Split-Path -Leaf $binary)
    if (!(Test-Path -LiteralPath $copy)) {Copy-Item -LiteralPath $binary -Destination $copy}
    if ((Get-FileHash -LiteralPath $copy).Hash -ne (Get-FileHash -LiteralPath $binary).Hash) {throw 'Portable engine bytes differ'}
}
New-Item -ItemType File -Force -Path (Join-Path $portableDir '_sc_') | Out-Null
$GodotPath=Join-Path $portableDir (Split-Path -Leaf $originalConsole)
function Invoke-Motion([string]$Label,[string[]]$Extra,[string]$Marker) {
    $phaseDir=Join-Path $motionReport $Label
    New-Item -ItemType Directory -Force -Path $phaseDir | Out-Null
    $baseArgs=@('--path',('"{0}"' -f $motionGame),'--audio-driver','Dummy','--log-file',('"{0}"' -f (Join-Path $phaseDir 'engine.log')))
    $p=Start-Process -FilePath $GodotPath -ArgumentList ($baseArgs+$Extra) -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $phaseDir 'stdout.log') -RedirectStandardError (Join-Path $phaseDir 'stderr.log')
    while (-not $p.WaitForExit(1000)) {
        $e=Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $phaseDir 'stderr.log') -ErrorAction SilentlyContinue
        if ($e -match 'SCRIPT ERROR|Assertion failed|Parse Error') { Stop-Process -Id $p.Id; throw $e }
    }
    $p.Refresh()
    [string]$stdout=Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $phaseDir 'stdout.log')
    [string]$stderr=Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $phaseDir 'stderr.log')
    $normalized=($stderr -replace "`r",'').Trim()
    $known="ERROR: Can't create shader cache folder, no shader caching will happen: user://`n   at: RasterizerGLES3 (drivers/gles3/rasterizer_gles3.cpp:335)"
    $profiler="ERROR: Could not open 'user://' directory: 'user://'.`n   at: _get_and_create_snapshot_storage_dir (modules/objectdb_profiler/editor/objectdb_profiler_panel.cpp:154)"
    $knownOnly=($normalized -eq $known -or $normalized -eq $profiler)
    $hasMarker=(!$Marker -or $stdout.Contains($Marker))
    @{engine_exit_code=$p.ExitCode;completion_marker=$hasMarker;stderr_empty=(!$normalized);shader_cache_diagnostic_only=($normalized -eq $known);editor_profiler_storage_diagnostic_only=($normalized -eq $profiler)} | ConvertTo-Json | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $phaseDir 'execution.json')
    if ($p.ExitCode -ne 0 -or !$hasMarker -or ($normalized -and !$knownOnly)) { throw "$Label failed: $stderr" }
}

if ($Phase -eq 'import') {
    Invoke-Motion 'import_initial' @('--headless','--editor','--import','--quit') ''
    Invoke-Motion 'import_settings' @('--headless','--script',('"{0}"' -f (Join-Path $PSScriptRoot 'configure_combat_import_v12.gd')),'--','--parts=res://assets/characters/player/run_arm_v21/','--version=v21') 'COMBAT_IMPORT_V12_CONFIGURED'
    Invoke-Motion 'import_final' @('--headless','--editor','--import','--quit') ''
} elseif ($Phase -eq 'parity') {
    Invoke-Motion 'parity' @('--resolution','1280x800','--position','-2000,-2000','--script',('"{0}"' -f (Join-Path $PSScriptRoot 'validate_combat_pose_v12.gd')),'--','--parts=res://assets/characters/player/run_arm_v21/','--version=v21',('"--reference={0}"' -f (Join-Path $motionRoot 'reports/run_arm_v21/export_reference.json')),('"--report={0}"' -f (Join-Path $motionReport 'godot_pose_parity.json'))) 'COMBAT_POSE_PARITY_V12_OK'
 } elseif ($Phase -eq 'gameplay') {
    Invoke-Motion 'gameplay' @('--resolution','1280x800','--position','-2000,-2000','--script','res://tests/player_visual.gd','--','--capture',('"--output={0}"' -f (Join-Path $motionReport 'gameplay'))) 'PLAYER_VISUAL_VALIDATION_COMPLETE'
 } elseif ($Phase -eq 'hands') {
    Invoke-Motion 'hands' @('--resolution','1280x800','--position','-2000,-2000','--script',('"{0}"' -f (Join-Path $PSScriptRoot 'test_right_hand_runtime_v20.gd')),'--',('"--report={0}"' -f (Join-Path $motionReport 'runtime_hand_validation.json'))) 'RIGHT_HAND_RUNTIME_V20_COMPLETE'
} elseif ($Phase -eq 'variants') {
    Invoke-Motion 'variants' @('--resolution','1280x800','--position','-2000,-2000','--script','res://tests/player_motion_v18.gd','--','--capture',('"--output={0}"' -f (Join-Path $motionReport 'variants'))) 'MOTION_VARIANTS_V18_COMPLETE'
}
Write-Output ('RUN_V21_GAME_'+$Phase.ToUpper()+'_OK')
