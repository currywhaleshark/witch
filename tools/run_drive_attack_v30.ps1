param([ValidateSet('import','validate','capture')][string]$Phase='validate')
$ErrorActionPreference='Stop'
$motionRoot=Split-Path -Parent $PSScriptRoot
$motionReport=Join-Path $motionRoot 'reports/drive_attack_v30'
$motionProject=Join-Path $motionReport 'project_snapshot'
$engine=Join-Path $motionRoot 'reports/combat_motion_v18/portable_godot/Godot_v4.6.2-stable_win64_console.exe'
$phaseDir=Join-Path $motionReport $Phase
New-Item -ItemType Directory -Force -Path $phaseDir | Out-Null
$arguments=@('--path',('"{0}"' -f $motionProject),'--audio-driver','Dummy','--log-file',('"{0}"' -f (Join-Path $phaseDir 'engine.log')))
if ($Phase -eq 'import') {
    $arguments+=@('--headless','--editor','--import','--quit')
} else {
    if ($Phase -eq 'validate') {$arguments+='--headless'}
    else {$arguments+=@('--resolution','1280x720','--position','-2000,-2000')}
    $arguments+=@('--script','res://tests/review_drive_attack_v30.gd','--',('"--output={0}"' -f $phaseDir))
    if ($Phase -eq 'validate') {$arguments+='--validate'}
}
$process=Start-Process -FilePath $engine -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $phaseDir 'stdout.log') -RedirectStandardError (Join-Path $phaseDir 'stderr.log')
while (-not $process.WaitForExit(1000)) {
    $diagnostics=Get-Content -LiteralPath (Join-Path $phaseDir 'stderr.log') -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
    if ($diagnostics -match 'SCRIPT ERROR|Assertion failed|Parse Error') {Stop-Process -Id $process.Id;throw $diagnostics}
}
$process.Refresh()
$stdout=Get-Content -LiteralPath (Join-Path $phaseDir 'stdout.log') -Raw -Encoding UTF8
$stderr=Get-Content -LiteralPath (Join-Path $phaseDir 'stderr.log') -Raw -Encoding UTF8
$marker=$Phase -eq 'import' -or $stdout.Contains('DRIVE_ATTACK_V30_REVIEW_COMPLETE')
@{exit_code=$process.ExitCode;completion_marker=$marker;stderr=$stderr} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $phaseDir 'execution.json') -Encoding UTF8
if ($process.ExitCode -ne 0 -or !$marker -or $stderr -match 'SCRIPT ERROR|Assertion failed|Parse Error') {throw "Review failed: $stderr"}
Write-Output $stdout
