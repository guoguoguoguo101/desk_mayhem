param([int]$Port = 24781, [switch]$Impaired, [switch]$Combo)
$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$output = Join-Path $project 'test_output'
New-Item -ItemType Directory -Force -Path $output | Out-Null
$processes = @()
try {
    $server = Start-Process godot_console.exe -WindowStyle Hidden -PassThru -ArgumentList @('--headless','--path',$project,'--script','res://server/battle_server.gd','--',"--port=$Port") -RedirectStandardOutput "$output/battle_server.out" -RedirectStandardError "$output/battle_server.err"
    $processes += $server
    for ($attempt=0; $attempt -lt 30; $attempt++) {
        if ((Test-Path "$output/battle_server.out") -and (Select-String -Path "$output/battle_server.out" -Pattern "listening port=$Port " -Quiet)) { break }
        Start-Sleep -Milliseconds 200
    }
    if (-not (Select-String -Path "$output/battle_server.out" -Pattern "listening port=$Port " -Quiet)) {
        Get-Content "$output/battle_server.err"
        throw 'Server startup failed'
    }
    foreach ($number in 1..2) {
        $scenario = if ($Combo) { '--battle-combo-smoke' } else { '--battle-client-smoke' }
        $clientPort = $Port
        if ($Impaired) {
            $clientPort = $Port + $number
            $proxies += @(Start-Process python -WindowStyle Hidden -PassThru -ArgumentList @("$project/tools/battle_udp_proxy.py",'--listen',$clientPort,'--server',$Port))
        }
        $processes += Start-Process godot_console.exe -WindowStyle Hidden -PassThru -ArgumentList @('--headless','--path',$project,'--',$scenario,"--port=$clientPort") -RedirectStandardOutput "$output/battle_client_$number.out" -RedirectStandardError "$output/battle_client_$number.err"
    }
    foreach ($client in $processes[1..2]) {
        if (-not $client.WaitForExit(25000)) { throw 'Client timed out' }
        if ($null -ne $client.ExitCode -and $client.ExitCode -ne 0) { throw "Client failed: $($client.ExitCode)" }
    }
    foreach ($number in 1..2) {
        if (-not (Select-String -Path "$output/battle_client_$number.out" -Pattern 'BATTLE_GAME_CLIENT PASS' -Quiet)) { throw 'Missing client PASS' }
    }
    if (Select-String -Path "$output/battle_*.err" -Pattern 'SCRIPT ERROR|Parse Error|Invalid call|Invalid access' -Quiet) { throw 'Runtime script errors' }
    Get-Content "$output/battle_client_1.out", "$output/battle_client_2.out"
    Write-Output 'BATTLE_INTEGRATION PASS'
} finally {
    foreach ($process in @($processes)+@($proxies)) {
        if ($null -eq $process) { continue }
        if (-not $process.HasExited) { Stop-Process -Id $process.Id -ErrorAction SilentlyContinue }
    }
}
