param(
    [ValidateSet('import','runtime','regressions')][string]$Phase = 'runtime',
    [string]$GodotPath = $env:GODOT_BIN,
    [ValidateSet('ground_loot','loot_resources','items','item_options')]
    [string[]]$Checks = @('ground_loot','loot_resources','items','item_options')
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$reportRoot = Join-Path $projectRoot 'reports/item_art_v2'
if (-not $GodotPath) {
    $installed = Get-Command godot -ErrorAction SilentlyContinue
    if ($installed) { $GodotPath = $installed.Source }
    else { $GodotPath = Join-Path $env:USERPROFILE 'Downloads/Godot_v4.6.2-stable_win64.exe/Godot_v4.6.2-stable_win64.exe' }
}
if (-not (Test-Path -LiteralPath $GodotPath)) { throw 'Pass -GodotPath or set GODOT_BIN to Godot 4.6.2.' }

function Invoke-ArtCheck([string]$Name, [string[]]$GodotArgs) {
    $checkDir = Join-Path $reportRoot $Name
    New-Item -ItemType Directory -Force $checkDir | Out-Null
    $arguments = @('--path', (Join-Path $projectRoot 'game'), '--audio-driver', 'Dummy',
                   '--log-file', (Join-Path $checkDir 'engine.log')) + $GodotArgs
    $quoted = @($arguments | ForEach-Object { '"' + $_.Replace('"','\"') + '"' })
    $started = Get-Date
    $process = Start-Process -FilePath $GodotPath -ArgumentList $quoted -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput (Join-Path $checkDir 'stdout.log') -RedirectStandardError (Join-Path $checkDir 'stderr.log')
    $process.WaitForExit()
    [ordered]@{exit_code=$process.ExitCode; command=@($GodotPath)+$arguments; seconds=((Get-Date)-$started).TotalSeconds} |
        ConvertTo-Json -Depth 4 | Set-Content (Join-Path $checkDir 'execution.json')
    Write-Output "$Name exit=$($process.ExitCode)"
    Get-Content (Join-Path $checkDir 'stdout.log') -Tail 3
    if ($process.ExitCode -ne 0) { throw "$Name failed; see $checkDir" }
}

if ($Phase -eq 'import') {
    Invoke-ArtCheck 'prepare' @('--headless','--script','res://tests/prepare_item_art_v2.gd')
    Invoke-ArtCheck 'import' @('--headless','--editor','--import')
} elseif ($Phase -eq 'runtime') {
    Invoke-ArtCheck 'runtime' @('--resolution','1280x800','--script','res://tests/item_art_v2.gd','--','--capture')
} else {
    $scriptRoot = Join-Path $reportRoot 'regression_scripts'
    New-Item -ItemType Directory -Force $scriptRoot | Out-Null
    foreach ($name in @($Checks | Where-Object { $_ -ne 'item_options' })) {
        $original = Join-Path $projectRoot "game/tests/$name.gd"
        $text = Get-Content -LiteralPath $original -Raw
        if ($name -eq 'items') { $text = $text.Replace('../reports/godot_items_report.json','../reports/item_art_v2/regressions/items/result.json') }
        else { $text = $text.Replace('res://../reports/loot_selection',"res://../reports/item_art_v2/regressions/$name") }
        $script = Join-Path $scriptRoot "$name.gd"
        [IO.File]::WriteAllText($script, $text, [Text.UTF8Encoding]::new($false))
        Invoke-ArtCheck "regressions/$name" @('--headless','--script',$script)
    }
    if ($Checks -contains 'item_options') {
        $result = Join-Path $reportRoot 'regressions/item_options/result.json'
        Invoke-ArtCheck 'regressions/item_options' @('--headless','--script','res://tests/item_options_v2.gd','--',"--output=$result")
    }
}
