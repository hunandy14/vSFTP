function Invoke-vSFTP {
    <#
    .SYNOPSIS
        執行帶有 SHA256 雜湊驗證的 SFTP 批次腳本。
    .DESCRIPTION
        解析並執行 SFTP 批次腳本，然後使用 SHA256 雜湊驗證所有傳輸的檔案。
    .PARAMETER ScriptFile
        SFTP 批次腳本的路徑。
    .PARAMETER NoVerify
        跳過雜湊驗證。
    .PARAMETER ContinueOnError
        即使檔案驗證失敗也繼續執行。
    .PARAMETER DryRun
        只解析腳本並顯示將執行的操作，不實際執行。
    .PARAMETER SkipHostKeyCheck
        跳過 SSH 主機金鑰驗證。
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
    
    # 結束代碼常數
    $script:EXIT_SUCCESS = 0
    $script:EXIT_VERIFY_FAILED = 1
    $script:EXIT_TRANSFER_FAILED = 2
    $script:EXIT_CONNECTION_FAILED = 3
    
    # 逾時設定
    $CONNECTION_TIMEOUT = 30
    
    # 追蹤 SSH session（用於 finally 清理）
    $sshSession = $null
    $exitCode = $EXIT_SUCCESS
    
    try {
        #region 顯示標題
        Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
        Write-Host "  vSFTP - SFTP with Hash Verification" -ForegroundColor Cyan
        Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
        Write-Host ""
        #endregion
        
        #region 驗證環境變數
        $missingVars = Test-Environment
        if ($missingVars.Count -gt 0) {
            foreach ($var in $missingVars) {
                Write-Host "✗ $var environment variable not set" -ForegroundColor Red
            }
            $exitCode = $EXIT_CONNECTION_FAILED
            return
        }
        
        $sftpHost = $env:SFTP_HOST
        $sftpUser = $env:SFTP_USER
        $sftpPort = if ($env:SFTP_PORT) { [int]$env:SFTP_PORT } else { 22 }
        $sftpKeyFile = $env:SFTP_KEYFILE
        
        Write-Host "Host: $sftpUser@$sftpHost`:$sftpPort" -ForegroundColor Gray
        Write-Host "Auth: Key ($sftpKeyFile)" -ForegroundColor Gray
        Write-Host ""
        #endregion
        
        #region 解析腳本
        Write-Host "► Parsing script: $ScriptFile" -ForegroundColor Yellow
        
        if (-not (Test-Path $ScriptFile)) {
            Write-Host "✗ Script file not found: $ScriptFile" -ForegroundColor Red
            $exitCode = $EXIT_TRANSFER_FAILED
            return
        }
        
        try {
            $operations = Parse-SftpScript -ScriptFile $ScriptFile -Verbose:$VerbosePreference
        } catch {
            Write-Host "✗ Failed to parse script: $_" -ForegroundColor Red
            $exitCode = $EXIT_TRANSFER_FAILED
            return
        }
        
        $putOps = @($operations | Where-Object { $_.Action -eq 'put' })
        $getOps = @($operations | Where-Object { $_.Action -eq 'get' })
        
        Write-Host "  Found $($putOps.Count) PUT operations" -ForegroundColor Gray
        Write-Host "  Found $($getOps.Count) GET operations" -ForegroundColor Gray
        Write-Host ""
        
        if ($operations.Count -eq 0) {
            Write-Host "✗ No transfer operations found in script" -ForegroundColor Red
            $exitCode = $EXIT_TRANSFER_FAILED
            return
        }
        #endregion
        
        #region 試執行模式
        if ($DryRun) {
            Write-Host "► Dry Run - Operations that would be performed:" -ForegroundColor Yellow
            Write-Host ""
            foreach ($op in $operations) {
                $arrow = if ($op.Action -eq 'put') { '→' } else { '←' }
                Write-Host "  [$($op.Action.ToUpper())] $($op.LocalPath) $arrow $($op.RemotePath)" -ForegroundColor Cyan
            }
            Write-Host ""
            Write-Host "Dry run complete. No files transferred." -ForegroundColor Green
            return
        }
        #endregion
        
        #region 建立 SSH 連線（用於雜湊驗證）
        $remoteOS = $null
        
        if (-not $NoVerify) {
            Write-Host "► Connecting SSH for hash verification..." -ForegroundColor Yellow
            
            $sshParams = @{
                ComputerName      = $sftpHost
                Port              = $sftpPort
                Credential        = New-Object PSCredential($sftpUser, (New-Object SecureString))
                KeyFile           = $sftpKeyFile
                ConnectionTimeout = $CONNECTION_TIMEOUT
                AcceptKey         = $true
            }
            
            if ($SkipHostKeyCheck) {
                $sshParams['Force'] = $true
            }
            
            $sshSession = New-SSHSession @sshParams
            
            if (-not $sshSession) {
                Write-Host "✗ SSH connection failed: Failed to create SSH session" -ForegroundColor Red
                $exitCode = $EXIT_CONNECTION_FAILED
                return
            }
            
            Write-Host "  Connected (Session $($sshSession.SessionId))" -ForegroundColor Gray
            
            # 偵測遠端作業系統
            $remoteOS = Get-RemoteOS -SessionId $sshSession.SessionId
            Write-Host "  Remote OS: $remoteOS" -ForegroundColor Gray
            Write-Host ""
        }
        #endregion
        
        #region 展開遠端萬用字元（GET 操作）
        if ($getOps.Count -gt 0 -and $sshSession) {
            $wildcardOps = @($getOps | Where-Object { $_.HasWildcard })
            
            if ($wildcardOps.Count -gt 0) {
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
        
        #region 傳輸前：取得 GET 操作的遠端雜湊
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
                        $exitCode = $EXIT_VERIFY_FAILED
                        return
                    }
                }
            }
            Write-Host ""
        }
        #endregion
        
        #region 執行傳輸
        Write-Host "► Executing SFTP transfer..." -ForegroundColor Yellow
        Write-Host ""
        
        $sftpResult = Invoke-SftpExe -ScriptFile $ScriptFile -Host $sftpHost -User $sftpUser -Port $sftpPort -KeyFile $sftpKeyFile -SkipHostKeyCheck:$SkipHostKeyCheck -Verbose:$VerbosePreference
        
        if ($sftpResult.ExitCode -ne 0) {
            Write-Host ""
            Write-Host "✗ SFTP transfer failed (exit code: $($sftpResult.ExitCode))" -ForegroundColor Red
            $exitCode = $EXIT_TRANSFER_FAILED
            return
        }
        
        Write-Host ""
        Write-Host "  Transfer completed" -ForegroundColor Gray
        Write-Host ""
        #endregion
        
        #region 雜湊驗證
        if (-not $NoVerify) {
            Write-Host "► Verifying file hashes..." -ForegroundColor Yellow
            Write-Host ""
            
            $passed = 0
            $failed = 0
            
            # 驗證 PUT 操作
            foreach ($op in $putOps) {
                $result = Test-FileHash -LocalPath $op.LocalPath -RemotePath $op.RemotePath -SessionId $sshSession.SessionId -RemoteOS $remoteOS -Action 'put'
                
                if ($result.Error) {
                    Write-Host "  ✗ $($op.RemotePath) - $($result.Error)" -ForegroundColor Red
                    $failed++
                } elseif ($result.Success) {
                    Write-Host "  ✓ $($op.RemotePath)" -ForegroundColor Green
                    $passed++
                } else {
                    Write-Host "  ✗ $($op.RemotePath) - HASH MISMATCH" -ForegroundColor Red
                    Write-Host "    Local:  $($result.LocalHash)" -ForegroundColor Red
                    Write-Host "    Remote: $($result.RemoteHash)" -ForegroundColor Red
                    $failed++
                }
                
                if ($failed -gt 0 -and -not $ContinueOnError) {
                    Write-Host ""
                    Write-Host "Aborting due to hash mismatch." -ForegroundColor Red
                    $exitCode = $EXIT_VERIFY_FAILED
                    return
                }
            }
            
            # 驗證 GET 操作
            foreach ($op in $getOps) {
                $expectedHash = $remoteHashes[$op.RemotePath]
                $result = Test-FileHash -LocalPath $op.LocalPath -RemotePath $op.RemotePath -ExpectedHash $expectedHash -Action 'get'
                
                if ($result.Error) {
                    Write-Host "  ⚠ $($op.LocalPath) - $($result.Error)" -ForegroundColor Yellow
                    continue
                } elseif ($result.Success) {
                    Write-Host "  ✓ $($op.LocalPath)" -ForegroundColor Green
                    $passed++
                } else {
                    Write-Host "  ✗ $($op.LocalPath) - HASH MISMATCH" -ForegroundColor Red
                    Write-Host "    Expected: $($result.RemoteHash)" -ForegroundColor Red
                    Write-Host "    Actual:   $($result.LocalHash)" -ForegroundColor Red
                    $failed++
                }
                
                if ($failed -gt 0 -and -not $ContinueOnError) {
                    Write-Host ""
                    Write-Host "Aborting due to hash mismatch." -ForegroundColor Red
                    $exitCode = $EXIT_VERIFY_FAILED
                    return
                }
            }
            
            # 顯示結果摘要
            Write-Host ""
            Write-Host "───────────────────────────────────────────────────────────────" -ForegroundColor Cyan
            Write-Host "  Summary: $passed passed, $failed failed" -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Red' })
            Write-Host "───────────────────────────────────────────────────────────────" -ForegroundColor Cyan
            
            if ($failed -gt 0) {
                $exitCode = $EXIT_VERIFY_FAILED
            }
        } else {
            Write-Host "► Hash verification skipped (-NoVerify)" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "───────────────────────────────────────────────────────────────" -ForegroundColor Cyan
            Write-Host "  Transfer completed (verification skipped)" -ForegroundColor Green
            Write-Host "───────────────────────────────────────────────────────────────" -ForegroundColor Cyan
        }
        #endregion
        
    } finally {
        # 確保 SSH session 被正確清理
        if ($sshSession) {
            Remove-SSHSession -SessionId $sshSession.SessionId -ErrorAction SilentlyContinue | Out-Null
        }
    }
    
    exit $exitCode
}
