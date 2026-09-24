param([int]$Port = 24680)
$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$output = Join-Path $project 'test_output'
New-Item -ItemType Directory -Force -Path $output | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$stdout = Join-Path $output "battle_live_$stamp.out"
$stderr = Join-Path $output "battle_live_$stamp.err"
$battle = Start-Process godot_console.exe -WindowStyle Hidden -PassThru -ArgumentList @('--headless','--path',$project,'--script','res://server/battle_server.gd','--',"--port=$Port") -RedirectStandardOutput $stdout -RedirectStandardError $stderr
Start-Sleep -Seconds 2
if ($battle.HasExited -or -not (Select-String -Path $stdout -Pattern "listening port=$Port " -Quiet)) {
    Get-Content $stderr
    throw 'Battle server did not start. Check port occupancy and script errors.'
}
Write-Output "Battle server running. PID=$($battle.Id) UDP=$Port"
Write-Output "Output: $stdout"
Write-Output "Errors: $stderr"
