#!/usr/bin/env pwsh
<#
.SYNOPSIS
    初始化 vSFTP 測試環境
.DESCRIPTION
    啟動 Docker 容器並設定好 SSH host key
.PARAMETER Down
    關閉並清理測試環境
.PARAMETER Reset
    重置環境（關閉後重新啟動）
.PARAMETER SkipHostKey
    跳過 host key 註冊（首次連線需手動輸入 yes 或使用 -SkipHostKeyCheck）
#>
param(
    [switch]$Down,
    [switch]$Reset,
    [switch]$SkipHostKey
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path $PSScriptRoot -Parent

# 載入環境變數
$envFile = Join-Path $PSScriptRoot ".env"
if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        if ($_ -match '^([^#][^=]+)=(.*)$') {
            [Environment]::SetEnvironmentVariable($Matches[1], $Matches[2])
        }
    }
}

$sshKnownHosts = Join-Path $HOME ".ssh/known_hosts"
$hostKeyEntry = "[localhost]:2222"

function Remove-HostKey {
    Write-Host "► 清理 host key..." -ForegroundColor Yellow
    
    # OpenSSH known_hosts
    if (Test-Path $sshKnownHosts) {
        $content = Get-Content $sshKnownHosts | Where-Object { $_ -notmatch [regex]::Escape($hostKeyEntry) }
        if ($content) {
            $content | Set-Content $sshKnownHosts
        } else {
            Remove-Item $sshKnownHosts -Force
        }
    }
    
    Write-Host "  完成" -ForegroundColor Green
}

function Start-TestServer {
    Write-Host "► 啟動測試伺服器..." -ForegroundColor Yellow
    Push-Location $ProjectRoot
    docker compose up -d
    Pop-Location
    
    Write-Host "  等待伺服器就緒..." -ForegroundColor Gray
    $maxRetries = 15
    for ($i = 1; $i -le $maxRetries; $i++) {
        Start-Sleep -Seconds 1
        $result = docker exec vsftp-test-server cat /config/.ssh/authorized_keys 2>$null
        if ($result) {
            Write-Host "  伺服器就緒" -ForegroundColor Green
            break
        }
        if ($i -eq $maxRetries) {
            throw "伺服器啟動逾時"
        }
        Write-Host "  等待中... ($i/$maxRetries)" -ForegroundColor Gray
    }
}

function Add-HostKey {
    Write-Host "► 註冊 host key（sftp.exe 用）..." -ForegroundColor Yellow
    
    # 用 ssh-keyscan 取得 host key（stderr 有註解，stdout 有 key）
    $hostKeys = ssh-keyscan -p 2222 localhost 2>&1 | Where-Object { $_ -notmatch '^#' -and $_ -match 'ssh-|ecdsa-' }
    
    if (-not $hostKeys) {
        throw "無法取得 host key"
    }
    
    # 確保 .ssh 目錄存在
    $sshDir = Split-Path $sshKnownHosts -Parent
    if (-not (Test-Path $sshDir)) {
        New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
    }
    
    # 加入 OpenSSH known_hosts（給 sftp.exe 用）
    $hostKeys | Add-Content -Path $sshKnownHosts
    
    Write-Host "  完成" -ForegroundColor Green
}

function Stop-TestServer {
    Write-Host "► 關閉測試伺服器..." -ForegroundColor Yellow
    Push-Location $ProjectRoot
    docker compose down
    Pop-Location
    Write-Host "  完成" -ForegroundColor Green
}

function Initialize-TestFiles {
    Write-Host "► 建立測試檔案..." -ForegroundColor Yellow
    
    $localDir = Join-Path $PSScriptRoot "local"
    $remoteDir = Join-Path $PSScriptRoot "remote"
    
    # 本地測試檔案
    "Hello vSFTP - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Set-Content (Join-Path $localDir "test.txt")
    
    # 遠端測試檔案
    "Remote file A" | Set-Content (Join-Path $remoteDir "remote-file.txt")
    "Log entry 1" | Set-Content (Join-Path $remoteDir "access.log")
    "Log entry 2" | Set-Content (Join-Path $remoteDir "error.log")
    
    Write-Host "  測試檔案已建立" -ForegroundColor Green
}

function Show-Info {
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  vSFTP 測試環境已就緒" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  連線資訊:" -ForegroundColor White
    Write-Host "    Host:    localhost:2222" -ForegroundColor Gray
    Write-Host "    User:    testuser" -ForegroundColor Gray
    Write-Host "    Key:     secrets/id_ed25519" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  測試指令:" -ForegroundColor White
    Write-Host '    $env:SFTP_HOST="localhost"; $env:SFTP_PORT="2222"' -ForegroundColor Gray
    Write-Host '    $env:SFTP_USER="testuser"; $env:SFTP_KEYFILE="secrets/id_ed25519"' -ForegroundColor Gray
    Write-Host '    Import-Module ./src/vSFTP.psd1' -ForegroundColor Gray
    Write-Host '    Invoke-vSFTP -ScriptFile test/scripts/test-upload.sftp' -ForegroundColor Gray
    Write-Host ""
    Write-Host "  關閉環境:" -ForegroundColor White
    Write-Host '    ./test/init.ps1 -Down' -ForegroundColor Gray
    Write-Host ""
}

# Main
Write-Host ""

if ($Down) {
    Stop-TestServer
    Remove-HostKey
    exit 0
}

if ($Reset) {
    Stop-TestServer
    Remove-HostKey
}

Remove-HostKey
Start-TestServer
if (-not $SkipHostKey) {
    Add-HostKey
}
Initialize-TestFiles
Show-Info
