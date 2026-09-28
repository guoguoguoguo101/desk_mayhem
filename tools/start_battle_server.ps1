param([int]$Port = 24680, [string]$Map = 'courtyard')
$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$output = Join-Path $project 'test_output'
New-Item -ItemType Directory -Force -Path $output | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$stdout = Join-Path $output "battle_live_$stamp.out"
$stderr = Join-Path $output "battle_live_$stamp.err"
$battle = Start-Process godot_console.exe -WindowStyle Hidden -PassThru -ArgumentList @('--headless','--path',$project,'--script','res://server/battle_server.gd','--',"--port=$Port","--map=$Map") -RedirectStandardOutput $stdout -RedirectStandardError $stderr
for ($attempt = 0; $attempt -lt 30; $attempt++) {
    if ((Test-Path $stdout) -and (Select-String -Path $stdout -Pattern "listening port=$Port " -Quiet)) { break }
    Start-Sleep -Milliseconds 200
}
if (-not (Select-String -Path $stdout -Pattern "listening port=$Port " -Quiet)) {
    Get-Content $stderr
    throw 'Battle server did not start. Check port occupancy and script errors.'
}
$listener = netstat -ano -p udp | Select-String ":$Port\s"
$listenerPid = $battle.Id
if ($listener) {
    $parts = ($listener[0].Line -split '\s+') | Where-Object { $_ }
    if ($parts.Count -ge 4) { $listenerPid = [int]$parts[-1] }
}
Write-Output "Battle server running. PID=$listenerPid UDP=$Port Map=$Map"
Write-Output "Output: $stdout"
Write-Output "Errors: $stderr"
