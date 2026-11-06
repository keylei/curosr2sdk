<#
.SYNOPSIS
  停止由 start.ps1 -Background 启动的 cursor-sdk2api 网关。
#>
$ErrorActionPreference = 'Stop'
$PidFile = Join-Path $PSScriptRoot 'logs\gateway.pid'

if (-not (Test-Path $PidFile)) {
    Write-Host "未找到 $PidFile，没有后台实例在运行（前台实例直接 Ctrl+C）"
    return
}

$gwPid = Get-Content $PidFile
if (Get-Process -Id $gwPid -ErrorAction SilentlyContinue) {
    Stop-Process -Id $gwPid -Force
    Write-Host "已停止网关 (PID $gwPid)"
} else {
    Write-Host "PID $gwPid 已不存在，清理残留 pid 文件"
}
Remove-Item $PidFile -Force
