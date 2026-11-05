param([string]$GodotPath = $env:GODOT_BIN, [switch]$ChecksOnly)
$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
if (-not $GodotPath) {
    $AvailableGodot = Get-Command godot -ErrorAction SilentlyContinue
    if ($AvailableGodot) { $GodotPath = $AvailableGodot.Source }
    else { $GodotPath = Join-Path $RepoRoot 'reports/combat_motion_v18/portable_godot/Godot_v4.6.2-stable_win64_console.exe' }
}
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw 'Provide -GodotPath or GODOT_BIN for Godot 4.6.' }
$GameRoot = Join-Path $RepoRoot 'game'
$ReportRoot = Join-Path $RepoRoot 'reports/hound_fullbody_v4'
$LogRoot = Join-Path $ReportRoot 'local'
New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null
& $GodotPath --headless --path $GameRoot --editor --import --log-file (Join-Path $LogRoot 'reimport.log')
if ($LASTEXITCODE -ne 0) { throw 'Godot import failed.' }
foreach ($Entry in @(@('hound',4), @('hound_armour',3))) {
    $ActorName = $Entry[0]
    & $GodotPath --headless --path $GameRoot --log-file (Join-Path $LogRoot ($ActorName + '_runtime.log')) --script res://tests/review_automation_actor_v1.gd -- ('--actor=' + $ActorName) ('--version=' + $Entry[1]) --checks-only ('--output=' + (Join-Path $ReportRoot ($ActorName + '/runtime')))
    if ($LASTEXITCODE -ne 0) { throw "Playback validation failed: $ActorName" }
}
if (-not $ChecksOnly) {
    & $GodotPath --path $GameRoot --rendering-method gl_compatibility --log-file (Join-Path $LogRoot 'gpu.log') --script res://tests/review_hound_fullbody_v4.gd -- ('--output=' + (Join-Path $ReportRoot 'comparison'))
    if ($LASTEXITCODE -ne 0) { throw 'GPU review failed.' }
}
