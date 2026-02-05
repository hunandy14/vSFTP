#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Run vSFTP tests against Docker test server.
.PARAMETER Setup
    Start Docker container and create test files.
.PARAMETER Teardown
    Stop and remove Docker container.
.PARAMETER SkipSetup
    Skip container setup (assume already running).
#>
param(
    [switch]$Setup,
    [switch]$Teardown,
    [switch]$SkipSetup
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path $PSScriptRoot -Parent

# Load environment variables
Get-Content "$PSScriptRoot/.env" | ForEach-Object {
    if ($_ -match '^([^#][^=]+)=(.*)$') {
        [Environment]::SetEnvironmentVariable($Matches[1], $Matches[2])
    }
}

function Start-TestServer {
    Write-Host "► Starting test server..." -ForegroundColor Yellow
    Push-Location $ProjectRoot
    docker compose up -d
    Pop-Location
    
    Write-Host "  Waiting for server to be ready..." -ForegroundColor Gray
    Start-Sleep -Seconds 5
    
    # Test connection
    $maxRetries = 10
    for ($i = 1; $i -le $maxRetries; $i++) {
        try {
            $null = Test-Connection -TcpPort 2222 -TargetName localhost -ErrorAction Stop
            Write-Host "  Server is ready" -ForegroundColor Green
            return
        } catch {
            if ($i -eq $maxRetries) {
                throw "Server failed to start"
            }
            Start-Sleep -Seconds 2
        }
    }
}

function Stop-TestServer {
    Write-Host "► Stopping test server..." -ForegroundColor Yellow
    Push-Location $ProjectRoot
    docker compose down
    Pop-Location
    Write-Host "  Done" -ForegroundColor Green
}

function Initialize-TestFiles {
    Write-Host "► Creating test files..." -ForegroundColor Yellow
    
    # Local test files
    $localDir = "$PSScriptRoot/local"
    "Hello from vSFTP test - $(Get-Date -Format 'o')" | Set-Content "$localDir/test.txt"
    "Line 1`nLine 2`nLine 3" | Set-Content "$localDir/multi.txt"
    
    # Remote test files (for download tests)
    $remoteDir = "$PSScriptRoot/remote"
    "Remote file content" | Set-Content "$remoteDir/remote-file.txt"
    
    Write-Host "  Created test files" -ForegroundColor Green
}

function Invoke-Tests {
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  Running vSFTP Tests" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""
    
    # Import module
    Import-Module "$ProjectRoot/vSFTP.psd1" -Force
    
    # Test 1: Dry Run
    Write-Host "─── Test 1: Dry Run ───" -ForegroundColor Magenta
    Invoke-vSFTP -ScriptFile "$PSScriptRoot/scripts/test-upload.sftp" -DryRun
    Write-Host ""
    
    # Test 2: Upload with verification
    Write-Host "─── Test 2: Upload with Verification ───" -ForegroundColor Magenta
    Invoke-vSFTP -ScriptFile "$PSScriptRoot/scripts/test-upload.sftp" -Verbose
    Write-Host ""
    
    # Test 3: Download with verification
    Write-Host "─── Test 3: Download with Verification ───" -ForegroundColor Magenta
    Invoke-vSFTP -ScriptFile "$PSScriptRoot/scripts/test-download.sftp" -Verbose
    Write-Host ""
    
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  All tests completed!" -ForegroundColor Green
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
}

# Main
if ($Teardown) {
    Stop-TestServer
    exit 0
}

if ($Setup -or -not $SkipSetup) {
    Start-TestServer
    Initialize-TestFiles
}

try {
    Invoke-Tests
} finally {
    if (-not $SkipSetup -and -not $Setup) {
        Stop-TestServer
    }
}
