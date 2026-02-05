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
    
    # 常數
    $EXIT_SUCCESS = 0
    $EXIT_VERIFY_FAILED = 1
    $EXIT_TRANSFER_FAILED = 2
    $EXIT_CONNECTION_FAILED = 3
    $CONNECTION_TIMEOUT = 30
    
    # 狀態變數
    $sshSession = $null
    $exitCode = $EXIT_SUCCESS
    
    try {
        Write-Banner
        
        #region 驗證環境變數
        $missingVars = Test-Environment
        if ($missingVars.Count -gt 0) {
            $missingVars | ForEach-Object { Write-Host "✗ $_ environment variable not set" -ForegroundColor Red }
            $exitCode = $EXIT_CONNECTION_FAILED
            return
        }
        
        $config = @{
            Host    = $env:SFTP_HOST
            User    = $env:SFTP_USER
            Port    = if ($env:SFTP_PORT) { [int]$env:SFTP_PORT } else { 22 }
            KeyFile = $env:SFTP_KEYFILE
        }
        
        Write-Host "Host: $($config.User)@$($config.Host):$($config.Port)" -ForegroundColor Gray
        Write-Host "Auth: Key ($($config.KeyFile))" -ForegroundColor Gray
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
        
        Write-Host "  Found $($putOps.Count) PUT, $($getOps.Count) GET operations" -ForegroundColor Gray
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
        
        #region 建立 SSH 連線
        $remoteOS = $null
        
        if (-not $NoVerify) {
            Write-Host "► Connecting SSH for hash verification..." -ForegroundColor Yellow
            
            $sshParams = @{
                ComputerName      = $config.Host
                Port              = $config.Port
                Credential        = New-Object PSCredential($config.User, (New-Object SecureString))
                KeyFile           = $config.KeyFile
                ConnectionTimeout = $CONNECTION_TIMEOUT
                AcceptKey         = $true
                Force             = $SkipHostKeyCheck.IsPresent
            }
            
            $sshSession = New-SSHSession @sshParams
            
            if (-not $sshSession) {
                Write-Host "✗ SSH connection failed" -ForegroundColor Red
                $exitCode = $EXIT_CONNECTION_FAILED
                return
            }
            
            Write-Host "  Connected (Session $($sshSession.SessionId))" -ForegroundColor Gray
            
            $remoteOS = Get-RemoteOS -SessionId $sshSession.SessionId
            Write-Host "  Remote OS: $remoteOS" -ForegroundColor Gray
            Write-Host ""
        }
        #endregion
        
        #region 展開萬用字元並取得 GET 的遠端雜湊
        $remoteHashes = @{}
        
        if (-not $NoVerify -and $getOps.Count -gt 0) {
            # 展開萬用字元
            $getOps = Expand-GetOperations -Operations $getOps -SessionId $sshSession.SessionId
            
            # 取得遠端雜湊
            Write-Host "► Getting remote hashes for GET operations..." -ForegroundColor Yellow
            foreach ($op in $getOps) {
                try {
                    $hash = Get-RemoteFileHash -SessionId $sshSession.SessionId -RemotePath $op.RemotePath -RemoteOS $remoteOS
                    $remoteHashes[$op.RemotePath] = $hash
                    Write-Host "  $($op.RemotePath): $($hash.Substring(0,16))..." -ForegroundColor Gray
                } catch {
                    Write-Host "  ✗ $($op.RemotePath): $_" -ForegroundColor Red
                    if (-not $ContinueOnError) { $exitCode = $EXIT_VERIFY_FAILED; return }
                }
            }
            Write-Host ""
        }
        #endregion
        
        #region 執行傳輸
        Write-Host "► Executing SFTP transfer..." -ForegroundColor Yellow
        Write-Host ""
        
        $sftpResult = Invoke-SftpExe -ScriptFile $ScriptFile -Host $config.Host -User $config.User -Port $config.Port -KeyFile $config.KeyFile -SkipHostKeyCheck:$SkipHostKeyCheck -Verbose:$VerbosePreference
        
        if ($sftpResult.ExitCode -ne 0) {
            Write-Host "`n✗ SFTP transfer failed (exit code: $($sftpResult.ExitCode))" -ForegroundColor Red
            $exitCode = $EXIT_TRANSFER_FAILED
            return
        }
        
        Write-Host "`n  Transfer completed`n" -ForegroundColor Gray
        #endregion
        
        #region 雜湊驗證
        if ($NoVerify) {
            Write-Host "► Hash verification skipped (-NoVerify)" -ForegroundColor Yellow
            Write-Summary -Skipped
            return
        }
        
        Write-Host "► Verifying file hashes..." -ForegroundColor Yellow
        Write-Host ""
        
        $passed = 0
        $failed = 0
        
        # 合併 PUT 和 GET 操作進行驗證
        $allOps = @()
        $allOps += $putOps | ForEach-Object { [PSCustomObject]@{ Op = $_; Action = 'put'; ExpectedHash = $null } }
        $allOps += $getOps | ForEach-Object { [PSCustomObject]@{ Op = $_; Action = 'get'; ExpectedHash = $remoteHashes[$_.RemotePath] } }
        
        foreach ($item in $allOps) {
            $op = $item.Op
            $displayPath = if ($item.Action -eq 'put') { $op.RemotePath } else { $op.LocalPath }
            
            $result = Test-FileHash -LocalPath $op.LocalPath -RemotePath $op.RemotePath `
                -SessionId $sshSession.SessionId -RemoteOS $remoteOS `
                -ExpectedHash $item.ExpectedHash -Action $item.Action
            
            if ($result.Error) {
                Write-Host "  ⚠ $displayPath - $($result.Error)" -ForegroundColor Yellow
            } elseif ($result.Success) {
                Write-Host "  ✓ $displayPath" -ForegroundColor Green
                $passed++
            } else {
                Write-Host "  ✗ $displayPath - HASH MISMATCH" -ForegroundColor Red
                Write-Host "    Expected: $($result.RemoteHash)" -ForegroundColor Red
                Write-Host "    Actual:   $($result.LocalHash)" -ForegroundColor Red
                $failed++
                
                if (-not $ContinueOnError) {
                    Write-Host "`nAborting due to hash mismatch." -ForegroundColor Red
                    $exitCode = $EXIT_VERIFY_FAILED
                    return
                }
            }
        }
        
        Write-Summary -Passed $passed -Failed $failed
        
        if ($failed -gt 0) {
            $exitCode = $EXIT_VERIFY_FAILED
        }
        #endregion
        
    } finally {
        if ($sshSession) {
            Remove-SSHSession -SessionId $sshSession.SessionId -ErrorAction SilentlyContinue | Out-Null
        }
    }
    
    exit $exitCode
}
