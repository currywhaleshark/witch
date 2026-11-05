param([string]$GodotPath=$env:GODOT_BIN,[switch]$ChecksOnly)
$ErrorActionPreference='Stop'
$repoPath=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not $GodotPath) {
    foreach ($name in @('godot','godot4','godot-console')) {
        $found=Get-Command $name -ErrorAction SilentlyContinue
        if ($found) { $GodotPath=$found.Source; break }
    }
}
if (-not $GodotPath) {
    $bundled=Join-Path $repoPath 'reports/combat_motion_v18/portable_godot/Godot_v4.6.2-stable_win64_console.exe'
    if (Test-Path -LiteralPath $bundled) { $GodotPath=$bundled }
}
if (-not $GodotPath) { throw 'Godot 4.6 executable required: use -GodotPath or GODOT_BIN.' }
$gamePath=Join-Path $repoPath 'game'
$reportPath=Join-Path $repoPath 'reports/automation_batch2_complete_v1'
$logPath=Join-Path $reportPath 'local'
New-Item -ItemType Directory -Force -Path $logPath | Out-Null
& $GodotPath --headless --path $gamePath --editor --import --quit --log-file (Join-Path $logPath 'import_engine.log')
if ($LASTEXITCODE) { throw 'Godot import failed.' }
foreach ($actorName in @('beacon','giant','hound_armour','giant_armour')) {
    $argsList=@('--path',$gamePath,'--script','res://tests/review_automation_actor_v1.gd','--log-file',(Join-Path $logPath "${actorName}_review_engine.log"))
    if ($ChecksOnly) { $argsList += '--headless' }
    else { $argsList += @('--rendering-method','gl_compatibility','--resolution','1000x760') }
    $actorOutput=Join-Path $reportPath "$actorName/runtime"
    if ($ChecksOnly) { $actorOutput=Join-Path $logPath "checks_$actorName" }
    $argsList += @('--',"--actor=$actorName","--output=$actorOutput")
    if ($ChecksOnly) { $argsList += '--checks-only' }
    & $GodotPath @argsList
    if ($LASTEXITCODE) { throw "$actorName review failed." }
}
if (-not $ChecksOnly) {
    & $GodotPath --path $gamePath --script res://tests/review_automation_batch2_complete_v1.gd --rendering-method gl_compatibility --resolution 1280x800 --log-file (Join-Path $logPath 'combined_review_engine.log') -- "--output=$(Join-Path $reportPath 'combined')"
    if ($LASTEXITCODE) { throw 'Combined review failed.' }
}
