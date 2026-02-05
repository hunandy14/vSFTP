function Invoke-vSFTP {
    <#
    .SYNOPSIS
        Execute SFTP batch script with SHA256 hash verification.
    .DESCRIPTION
        Parses and executes an SFTP batch script, then verifies all transferred
        files using SHA256 hashes.
    .PARAMETER ScriptFile
        Path to SFTP batch script.
    .PARAMETER NoVerify
        Skip hash verification.
    .PARAMETER ContinueOnError
        Continue execution even if a file fails verification.
    .PARAMETER DryRun
        Parse script and show what would be done without executing.
    .EXAMPLE
        $env:SFTP_HOST = "example.com"
        $env:SFTP_USER = "user"
        $env:SFTP_KEYFILE = "~/.ssh/id_rsa"
        Invoke-vSFTP -ScriptFile ./upload.sftp
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$ScriptFile,
        
        [switch]$NoVerify,
        
        [switch]$ContinueOnError,
        
        [switch]$DryRun,
        
        [switch]$SkipHostKeyCheck
    )
    
    # Exit codes
    $EXIT_SUCCESS = 0
    $EXIT_VERIFY_FAILED = 1
    $EXIT_TRANSFER_FAILED = 2
    $EXIT_CONNECTION_FAILED = 3
    
    # Timeouts
    $CONNECTION_TIMEOUT = 30
    $COMMAND_TIMEOUT = 300
    
    #region Validate Environment
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  vSFTP - SFTP with Hash Verification" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""
    
    $sftpHost = $env:SFTP_HOST
    $sftpUser = $env:SFTP_USER
    $sftpPort = if ($env:SFTP_PORT) { [int]$env:SFTP_PORT } else { 22 }
    $sftpKeyFile = $env:SFTP_KEYFILE
    
    if (-not $sftpHost) {
        Write-Host "✗ SFTP_HOST environment variable not set" -ForegroundColor Red
        exit $EXIT_CONNECTION_FAILED
    }
    if (-not $sftpUser) {
        Write-Host "✗ SFTP_USER environment variable not set" -ForegroundColor Red
        exit $EXIT_CONNECTION_FAILED
    }
    if (-not $sftpKeyFile) {
        Write-Host "✗ SFTP_KEYFILE environment variable not set" -ForegroundColor Red
        exit $EXIT_CONNECTION_FAILED
    }
    
    Write-Host "Host: $sftpUser@$sftpHost`:$sftpPort" -ForegroundColor Gray
    Write-Host "Auth: Key ($sftpKeyFile)" -ForegroundColor Gray
    Write-Host ""
    #endregion
    
    #region Parse Script
    Write-Host "► Parsing script: $ScriptFile" -ForegroundColor Yellow
    
    if (-not (Test-Path $ScriptFile)) {
        Write-Host "✗ Script file not found: $ScriptFile" -ForegroundColor Red
        exit $EXIT_TRANSFER_FAILED
    }
    
    try {
        $operations = Parse-SftpScript -ScriptFile $ScriptFile -Verbose:$VerbosePreference
    } catch {
        Write-Host "✗ Failed to parse script: $_" -ForegroundColor Red
        exit $EXIT_TRANSFER_FAILED
    }
    
    $putOps = @($operations | Where-Object { $_.Action -eq 'put' })
    $getOps = @($operations | Where-Object { $_.Action -eq 'get' })
    
    Write-Host "  Found $($putOps.Count) PUT operations" -ForegroundColor Gray
    Write-Host "  Found $($getOps.Count) GET operations" -ForegroundColor Gray
    Write-Host ""
    
    if ($operations.Count -eq 0) {
        Write-Host "✗ No transfer operations found in script" -ForegroundColor Red
        exit $EXIT_TRANSFER_FAILED
    }
    #endregion
    
    #region Dry Run
    if ($DryRun) {
        Write-Host "► Dry Run - Operations that would be performed:" -ForegroundColor Yellow
        Write-Host ""
        foreach ($op in $operations) {
            $arrow = if ($op.Action -eq 'put') { '→' } else { '←' }
            Write-Host "  [$($op.Action.ToUpper())] $($op.LocalPath) $arrow $($op.RemotePath)" -ForegroundColor Cyan
        }
        Write-Host ""
        Write-Host "Dry run complete. No files transferred." -ForegroundColor Green
        exit $EXIT_SUCCESS
    }
    #endregion
    
    #region Connect SSH (for hash verification)
    $sshSession = $null
    $remoteOS = $null
    
    if (-not $NoVerify) {
        Write-Host "► Connecting SSH for hash verification..." -ForegroundColor Yellow
        
        try {
            $sshParams = @{
                ComputerName = $sftpHost
                Port         = $sftpPort
                Credential   = New-Object PSCredential($sftpUser, (New-Object SecureString))
                KeyFile      = $sftpKeyFile
                ConnectionTimeout = $CONNECTION_TIMEOUT
                AcceptKey    = $true
            }
            
            if ($SkipHostKeyCheck) {
                $sshParams['Force'] = $true
            }
            
            $sshSession = New-SSHSession @sshParams
            
            if (-not $sshSession) {
                throw "Failed to create SSH session"
            }
            
            Write-Host "  Connected (Session $($sshSession.SessionId))" -ForegroundColor Gray
            
            # Detect remote OS
            $remoteOS = Get-RemoteOS -SessionId $sshSession.SessionId
            Write-Host "  Remote OS: $remoteOS" -ForegroundColor Gray
            Write-Host ""
            
        } catch {
            Write-Host "✗ SSH connection failed: $_" -ForegroundColor Red
            exit $EXIT_CONNECTION_FAILED
        }
    }
    #endregion
    
    #region Expand remote wildcards for GET operations
    if ($getOps.Count -gt 0) {
        $wildcardOps = @($getOps | Where-Object { $_.HasWildcard })
        
        if ($wildcardOps.Count -gt 0 -and $sshSession) {
            Write-Host "► Expanding remote wildcards..." -ForegroundColor Yellow
            
            $expandedOps = @()
            foreach ($op in $getOps) {
                if ($op.HasWildcard) {
                    $remoteFiles = Expand-RemoteWildcard -SessionId $sshSession.SessionId -RemotePath $op.RemotePath
                    
                    if ($remoteFiles.Count -eq 0) {
                        Write-Host "  ⚠ No files match: $($op.RemotePath)" -ForegroundColor Yellow
                        continue
                    }
                    
                    foreach ($remoteFile in $remoteFiles) {
                        $fileName = Split-Path $remoteFile -Leaf
                        $localDir = Split-Path $op.LocalPath -Parent
                        $localPath = Join-Path $localDir $fileName
                        
                        $expandedOps += [PSCustomObject]@{
                            Action      = 'get'
                            LocalPath   = $localPath
                            RemotePath  = $remoteFile
                            Line        = $op.Line
                            HasWildcard = $false
                        }
                        Write-Host "  $($op.RemotePath) → $remoteFile" -ForegroundColor Gray
                    }
                } else {
                    $expandedOps += $op
                }
            }
            
            $getOps = $expandedOps
            Write-Host "  Expanded to $($getOps.Count) files" -ForegroundColor Gray
            Write-Host ""
        }
    }
    #endregion
    
    #region Pre-transfer: Get remote hashes for GET operations
    $remoteHashes = @{}
    
    if (-not $NoVerify -and $getOps.Count -gt 0) {
        Write-Host "► Getting remote hashes for GET operations..." -ForegroundColor Yellow
        
        foreach ($op in $getOps) {
            
            try {
                $hash = Get-RemoteFileHash -SessionId $sshSession.SessionId -RemotePath $op.RemotePath -RemoteOS $remoteOS
                $remoteHashes[$op.RemotePath] = $hash
                Write-Host "  $($op.RemotePath): $($hash.Substring(0,16))..." -ForegroundColor Gray
            } catch {
                Write-Host "  ✗ $($op.RemotePath): $_" -ForegroundColor Red
                if (-not $ContinueOnError) {
                    if ($sshSession) { Remove-SSHSession -SessionId $sshSession.SessionId | Out-Null }
                    exit $EXIT_VERIFY_FAILED
                }
            }
        }
        Write-Host ""
    }
    #endregion
    
    #region Execute Transfer
    Write-Host "► Executing SFTP transfer..." -ForegroundColor Yellow
    Write-Host ""
    
    try {
        $sftpResult = Invoke-SftpExe -ScriptFile $ScriptFile -Host $sftpHost -User $sftpUser -Port $sftpPort -KeyFile $sftpKeyFile -SkipHostKeyCheck:$SkipHostKeyCheck -Verbose:$VerbosePreference
        
        if ($sftpResult.ExitCode -ne 0) {
            Write-Host ""
            Write-Host "✗ SFTP transfer failed (exit code: $($sftpResult.ExitCode))" -ForegroundColor Red
            if ($sshSession) { Remove-SSHSession -SessionId $sshSession.SessionId | Out-Null }
            exit $EXIT_TRANSFER_FAILED
        }
        
        Write-Host ""
        Write-Host "  Transfer completed" -ForegroundColor Gray
        Write-Host ""
        
    } catch {
        Write-Host ""
        Write-Host "✗ SFTP execution failed: $_" -ForegroundColor Red
        if ($sshSession) { Remove-SSHSession -SessionId $sshSession.SessionId | Out-Null }
        exit $EXIT_TRANSFER_FAILED
    }
    #endregion
    
    #region Hash Verification
    if (-not $NoVerify) {
        Write-Host "► Verifying file hashes..." -ForegroundColor Yellow
        Write-Host ""
        
        $passed = 0
        $failed = 0
        
        # Verify PUT operations
        foreach ($op in $putOps) {
            try {
                $localHash = Get-LocalFileHash -Path $op.LocalPath
                $remoteHash = Get-RemoteFileHash -SessionId $sshSession.SessionId -RemotePath $op.RemotePath -RemoteOS $remoteOS
                
                if ($localHash -eq $remoteHash) {
                    Write-Host "  ✓ $($op.RemotePath)" -ForegroundColor Green
                    $passed++
                } else {
                    Write-Host "  ✗ $($op.RemotePath) - HASH MISMATCH" -ForegroundColor Red
                    Write-Host "    Local:  $localHash" -ForegroundColor Red
                    Write-Host "    Remote: $remoteHash" -ForegroundColor Red
                    $failed++
                    
                    if (-not $ContinueOnError) {
                        Write-Host ""
                        Write-Host "Aborting due to hash mismatch." -ForegroundColor Red
                        if ($sshSession) { Remove-SSHSession -SessionId $sshSession.SessionId | Out-Null }
                        exit $EXIT_VERIFY_FAILED
                    }
                }
            } catch {
                Write-Host "  ✗ $($op.RemotePath) - $_" -ForegroundColor Red
                $failed++
                
                if (-not $ContinueOnError) {
                    if ($sshSession) { Remove-SSHSession -SessionId $sshSession.SessionId | Out-Null }
                    exit $EXIT_VERIFY_FAILED
                }
            }
        }
        
        # Verify GET operations
        foreach ($op in $getOps) {
            try {
                $localHash = Get-LocalFileHash -Path $op.LocalPath
                $expectedHash = $remoteHashes[$op.RemotePath]
                
                if (-not $expectedHash) {
                    Write-Host "  ⚠ $($op.LocalPath) - No pre-transfer hash recorded" -ForegroundColor Yellow
                    continue
                }
                
                if ($localHash -eq $expectedHash) {
                    Write-Host "  ✓ $($op.LocalPath)" -ForegroundColor Green
                    $passed++
                } else {
                    Write-Host "  ✗ $($op.LocalPath) - HASH MISMATCH" -ForegroundColor Red
                    Write-Host "    Expected: $expectedHash" -ForegroundColor Red
                    Write-Host "    Actual:   $localHash" -ForegroundColor Red
                    $failed++
                    
                    if (-not $ContinueOnError) {
                        Write-Host ""
                        Write-Host "Aborting due to hash mismatch." -ForegroundColor Red
                        if ($sshSession) { Remove-SSHSession -SessionId $sshSession.SessionId | Out-Null }
                        exit $EXIT_VERIFY_FAILED
                    }
                }
            } catch {
                Write-Host "  ✗ $($op.LocalPath) - $_" -ForegroundColor Red
                $failed++
                
                if (-not $ContinueOnError) {
                    if ($sshSession) { Remove-SSHSession -SessionId $sshSession.SessionId | Out-Null }
                    exit $EXIT_VERIFY_FAILED
                }
            }
        }
        
        Write-Host ""
        Write-Host "───────────────────────────────────────────────────────────────" -ForegroundColor Cyan
        Write-Host "  Summary: $passed passed, $failed failed" -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Red' })
        Write-Host "───────────────────────────────────────────────────────────────" -ForegroundColor Cyan
        
        # Cleanup
        if ($sshSession) {
            Remove-SSHSession -SessionId $sshSession.SessionId | Out-Null
        }
        
        if ($failed -gt 0) {
            exit $EXIT_VERIFY_FAILED
        }
    } else {
        Write-Host "► Hash verification skipped (-NoVerify)" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "───────────────────────────────────────────────────────────────" -ForegroundColor Cyan
        Write-Host "  Transfer completed (verification skipped)" -ForegroundColor Green
        Write-Host "───────────────────────────────────────────────────────────────" -ForegroundColor Cyan
    }
    #endregion
    
    exit $EXIT_SUCCESS
}
