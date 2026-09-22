# 同一台电脑上跑主机和客户端，检查移动、跳跃、击飞是否一致。
# 使用 24681，不会占用正在进行的比武端口 24680。
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$out = Join-Path $root "test_output"
New-Item -ItemType Directory -Force -Path $out | Out-Null
Remove-Item (Join-Path $out "pvp_host.txt"), (Join-Path $out "pvp_join.txt") -ErrorAction SilentlyContinue

$hostLog = Join-Path $out "pvp_host_console.txt"
$joinLog = Join-Path $out "pvp_join_console.txt"
$hostErr = Join-Path $out "pvp_host_err.txt"
$joinErr = Join-Path $out "pvp_join_err.txt"
Remove-Item $hostLog, $joinLog, $hostErr, $joinErr -ErrorAction SilentlyContinue

$godot = "godot_console.exe"
$hostProc = Start-Process -FilePath $godot -ArgumentList @(
	"--headless", "--path", $root, "--", "--pvp-test=host"
) -RedirectStandardOutput $hostLog -RedirectStandardError $hostErr -PassThru -WindowStyle Hidden
Start-Sleep -Seconds 1.2
$joinProc = Start-Process -FilePath $godot -ArgumentList @(
	"--headless", "--path", $root, "--", "--pvp-test=join"
) -RedirectStandardOutput $joinLog -RedirectStandardError $joinErr -PassThru -WindowStyle Hidden

$deadline = (Get-Date).AddSeconds(24)
$hostResult = Join-Path $out "pvp_host.txt"
$joinResult = Join-Path $out "pvp_join.txt"
while ((Get-Date) -lt $deadline) {
	$hostDone = (Test-Path $hostResult) -and (Select-String -Path $hostResult -Pattern "^DONE$" -Quiet)
	$joinDone = (Test-Path $joinResult) -and (Select-String -Path $joinResult -Pattern "^DONE$" -Quiet)
	if ($hostDone -and $joinDone) { break }
	Start-Sleep -Milliseconds 300
}

if (-not $hostProc.HasExited) { Stop-Process -Id $hostProc.Id -Force -ErrorAction SilentlyContinue }
if (-not $joinProc.HasExited) { Stop-Process -Id $joinProc.Id -Force -ErrorAction SilentlyContinue }
$hostProc.WaitForExit()
$joinProc.WaitForExit()

Write-Output "===== 主机 ====="
if (Test-Path $hostResult) { Get-Content $hostResult } else { Write-Output "没有结果" }
Write-Output "===== 客户端 ====="
if (Test-Path $joinResult) { Get-Content $joinResult } else { Write-Output "没有结果" }

$hostOk = (Test-Path $hostResult) -and ((Get-Content $hostResult -TotalCount 1) -eq "PASS")
$joinOk = (Test-Path $joinResult) -and ((Get-Content $joinResult -TotalCount 1) -eq "PASS")
if ($hostOk -and $joinOk) {
	Write-Output "PVP_TEST PASS"
	exit 0
}
Write-Output "PVP_TEST FAIL"
if (Test-Path $hostErr) { Write-Output "----- host err -----"; Get-Content $hostErr }
if (Test-Path $joinErr) { Write-Output "----- join err -----"; Get-Content $joinErr }
exit 1
