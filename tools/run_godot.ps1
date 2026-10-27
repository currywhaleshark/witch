param(
    [string]$GodotPath,
    [switch]$Verify,
    [switch]$RenderCheck,
    [switch]$Editor
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$gamePath = Join-Path $projectRoot 'game'

if (-not $GodotPath) {
    $engineCommand = Get-Command godot, godot4 -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($engineCommand) { $GodotPath = $engineCommand.Source }
}
if (-not $GodotPath) {
    # Portable Windows downloads: check a file or the common same-named extracted folder.
    $downloadsPath = Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads'
    $candidates = @()
    foreach ($entry in Get-ChildItem -LiteralPath $downloadsPath -Filter 'Godot_v4*win64*' -ErrorAction SilentlyContinue) {
        if ($entry.PSIsContainer) {
            $candidates += Get-ChildItem -LiteralPath $entry.FullName -Filter '*console.exe' -File
        } elseif ($entry.Extension -eq '.exe') {
            $candidates += $entry
        }
    }
    $GodotPath = ($candidates | Sort-Object Name -Descending | Select-Object -First 1).FullName
}
if (-not $GodotPath -or -not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw 'Godot 4.6 executable not found. Pass -GodotPath <absolute executable path>.'
}

$script:godotRunIndex = 0
function Invoke-Godot([string[]]$EngineArguments) {
    $script:godotRunIndex += 1
    $logPath = Join-Path $projectRoot "reports/godot_run_$($script:godotRunIndex)_runtime.log"
    & $GodotPath @EngineArguments --log-file $logPath
    if ($LASTEXITCODE -ne 0) { throw "Godot exited with code $LASTEXITCODE" }
    if (Select-String -LiteralPath $logPath -Pattern '^(SCRIPT ERROR|ERROR):' -Quiet) {
        throw "Godot reported runtime errors. See $logPath"
    }
}

# A fresh checkout needs the audio import cache before either testing or playing.
Invoke-Godot -EngineArguments @('--headless', '--path', $gamePath, '--editor', '--import', '--quit')
if ($Verify) {
    Invoke-Godot -EngineArguments @('--headless', '--path', $gamePath, '--script', 'res://tests/replay_rules.gd')
    Invoke-Godot -EngineArguments @('--headless', '--path', $gamePath, '--script', 'res://tests/smoke_arena.gd')
    Invoke-Godot -EngineArguments @('--headless', '--path', $gamePath, '--script', 'res://tests/approach_cast.gd')
    Invoke-Godot -EngineArguments @('--headless', '--path', $gamePath, '--script', 'res://tests/hold_input.gd')
    Invoke-Godot -EngineArguments @('--headless', '--path', $gamePath, '--script', 'res://tests/mana_a5.gd')
    Invoke-Godot -EngineArguments @('--headless', '--path', $gamePath, '--script', 'res://tests/tool_switch.gd')
    Invoke-Godot -EngineArguments @('--headless', '--path', $gamePath, '--script', 'res://tests/hit_block.gd')
    Invoke-Godot -EngineArguments @('--headless', '--path', $gamePath, '--script', 'res://tests/potions.gd')
    Invoke-Godot -EngineArguments @('--headless', '--path', $gamePath, '--script', 'res://tests/grades_hits.gd')
    Invoke-Godot -EngineArguments @('--headless', '--path', $gamePath, '--script', 'res://tests/enemy_types.gd')
    Invoke-Godot -EngineArguments @('--headless', '--path', $gamePath, '--script', 'res://tests/boss.gd')
    Invoke-Godot -EngineArguments @('--headless', '--path', $gamePath, '--script', 'res://tests/player_visual.gd')
}
if ($RenderCheck) {
    Invoke-Godot -EngineArguments @('--path', $gamePath, '--audio-driver', 'Dummy', '--script', 'res://tests/smoke_arena.gd')
}
if (-not $Verify -and -not $RenderCheck) {
    if ($Editor) { Invoke-Godot -EngineArguments @('--path', $gamePath, '--editor') }
    else { Invoke-Godot -EngineArguments @('--path', $gamePath) }
}
