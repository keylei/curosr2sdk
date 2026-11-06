<#
.SYNOPSIS
  启动 cursor-sdk2api 网关（官方 @cursor/sdk → OpenAI / Anthropic 兼容接口）。
.DESCRIPTION
  配置从同目录 .env.local 读取，缺省值在脚本内补齐。
  默认前台运行，Ctrl+C 退出；加 -Background 则脱离终端后台运行，
  日志写入 logs\，PID 写入 logs\gateway.pid，用 stop.ps1 停止。
.EXAMPLE
  .\start.ps1
  .\start.ps1 -Background
#>
[CmdletBinding()]
param(
    [switch]$Background
)

$ErrorActionPreference = 'Stop'
$Root    = $PSScriptRoot
$EnvFile = Join-Path $Root '.env.local'
$LogDir  = Join-Path $Root 'logs'
$PidFile = Join-Path $LogDir 'gateway.pid'

if (-not (Test-Path (Join-Path $Root 'dist\index.js'))) {
    throw "未找到 dist\index.js，请先在 $Root 执行 npm ci 和 npm run build"
}
if (-not (Test-Path $EnvFile)) {
    throw "未找到配置文件 $EnvFile"
}

# 读取 .env.local
Get-Content $EnvFile | ForEach-Object {
    $line = $_.Trim()
    if ($line -eq '' -or $line.StartsWith('#')) { return }
    $idx = $line.IndexOf('=')
    if ($idx -lt 1) { return }
    $name  = $line.Substring(0, $idx).Trim()
    $value = $line.Substring($idx + 1).Trim()
    Set-Item -Path "Env:$name" -Value $value
}

# 缺省值
if (-not $env:HOST)      { $env:HOST = '127.0.0.1' }
if (-not $env:PORT)      { $env:PORT = '8080' }
if (-not $env:AUTH_MODE) { $env:AUTH_MODE = 'managed' }
if (-not $env:STATE_DIR) { $env:STATE_DIR = Join-Path $Root 'state' }
if (-not $env:NO_PROXY)  { $env:NO_PROXY = '127.0.0.1,localhost' }
if (-not $env:GATEWAY_ACCESS_KEY) { throw "GATEWAY_ACCESS_KEY 未设置，请在 $EnvFile 中填写" }

New-Item -ItemType Directory -Force -Path $env:STATE_DIR, $LogDir | Out-Null

# 已有后台实例则不重复启动
if (Test-Path $PidFile) {
    $oldPid = Get-Content $PidFile -ErrorAction SilentlyContinue
    if ($oldPid -and (Get-Process -Id $oldPid -ErrorAction SilentlyContinue)) {
        Write-Host "网关已在后台运行 (PID $oldPid)，如需重启请先执行 .\stop.ps1"
        return
    }
    Remove-Item $PidFile -Force
}

$baseUrl = "http://$($env:HOST):$($env:PORT)"
Write-Host "cursor-sdk2api  $baseUrl"
Write-Host "  控制台    $baseUrl/console/"
Write-Host "  STATE_DIR $env:STATE_DIR"
Write-Host "  出站代理  $(if ($env:HTTPS_PROXY) { $env:HTTPS_PROXY } else { '未配置（直连）' })"

if (-not $Background) {
    Push-Location $Root
    try { node dist/index.js } finally { Pop-Location }
    return
}

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$proc = Start-Process -FilePath 'node' -ArgumentList 'dist/index.js' -WorkingDirectory $Root `
    -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput (Join-Path $LogDir "gateway_$stamp.out.log") `
    -RedirectStandardError  (Join-Path $LogDir "gateway_$stamp.err.log")
$proc.Id | Set-Content $PidFile

# 等待 /health 就绪
for ($i = 0; $i -lt 20; $i++) {
    Start-Sleep -Milliseconds 500
    try {
        $resp = Invoke-RestMethod -Uri "$baseUrl/health" -TimeoutSec 2
        Write-Host "后台已启动 (PID $($proc.Id))，/health："
        $resp | ConvertTo-Json -Depth 4
        return
    } catch { }
    if ($proc.HasExited) { break }
}
Write-Warning "进程未在预期时间内就绪，请查看 $LogDir 下最新日志"
