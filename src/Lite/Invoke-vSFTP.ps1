function Invoke-vSFTP {
    <#
    .SYNOPSIS
        執行帶有 SHA256 雜湊驗證的 SFTP 批次腳本（輕量版，使用 ssh/sftp 指令）。
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
    .PARAMETER Connection
        連線字串，格式：HostName=<host>;User=<user>[;IdentityFile=<keypath>][;Port=<port>]
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][string]$ScriptFile,
        [string]$Connection,
        [switch]$NoVerify,
        [switch]$ContinueOnError,
        [switch]$DryRun,
        [switch]$SkipHostKeyCheck
    )

    $EXIT_SUCCESS = 0; $EXIT_VERIFY_FAILED = 1; $EXIT_TRANSFER_FAILED = 2; $EXIT_CONNECTION_FAILED = 3
    $exitCode = $EXIT_SUCCESS

    try {
        Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
        Write-Host "  vSFTP Lite - SFTP with Hash Verification" -ForegroundColor Cyan
        Write-Host "═══════════════════════════════════════════════════════════════`n" -ForegroundColor Cyan

        # 解析連線設定
        $connStr = if ($Connection) { $Connection } else { $env:SFTP_CONNECTION }
        
        if (-not $connStr) {
            Write-Host "✗ SFTP_CONNECTION not set" -ForegroundColor Red
            Write-Host "  Format: HostName=<host>;User=<user>[;IdentityFile=<keypath>][;Port=<port>]" -ForegroundColor Gray
            $exitCode = $EXIT_CONNECTION_FAILED; return
        }

        try {
            $config = ConvertFrom-ConnectionString -ConnectionString $connStr
        } catch {
            Write-Host "✗ $_" -ForegroundColor Red
            $exitCode = $EXIT_CONNECTION_FAILED; return
        }
        
        $sshHost = "$($config.User)@$($config.Host)"
        Write-Host "Host: $sshHost`:$($config.Port)" -ForegroundColor Gray
        Write-Host "Key:  $(if ($config.KeyFile) { $config.KeyFile } else { '(auto-detect)' })`n" -ForegroundColor Gray

        # 解析腳本
        Write-Host "► Parsing: $ScriptFile" -ForegroundColor Yellow
        if (-not (Test-Path $ScriptFile)) {
            Write-Host "✗ File not found" -ForegroundColor Red
            $exitCode = $EXIT_TRANSFER_FAILED; return
        }

        try { $operations = ConvertFrom-SftpScript -ScriptFile $ScriptFile -Verbose:$VerbosePreference }
        catch { Write-Host "✗ Parse failed: $_" -ForegroundColor Red; $exitCode = $EXIT_TRANSFER_FAILED; return }

        $putOps = @($operations | Where-Object { $_.Action -eq 'put' })
        $getOps = @($operations | Where-Object { $_.Action -eq 'get' })
        Write-Host "  $($putOps.Count) PUT, $($getOps.Count) GET`n" -ForegroundColor Gray

        if ($operations.Count -eq 0) {
            Write-Host "✗ No operations found" -ForegroundColor Red
            $exitCode = $EXIT_TRANSFER_FAILED; return
        }

        # DryRun
        if ($DryRun) {
            Write-Host "► Dry Run:`n" -ForegroundColor Yellow
            $operations | ForEach-Object {
                $arrow = if ($_.Action -eq 'put') { '→' } else { '←' }
                Write-Host "  [$($_.Action.ToUpper())] $($_.LocalPath) $arrow $($_.RemotePath)" -ForegroundColor Cyan
            }
            Write-Host "`nNo files transferred." -ForegroundColor Green
            return
        }

        # 偵測遠端 OS（驗證模式）
        $remoteOS = $null; $remoteHashes = @{}; $remotePaths = @{}

        if (-not $NoVerify) {
            Write-Host "► Detecting remote OS..." -ForegroundColor Yellow
            
            $sshParams = @{
                SshHost = $sshHost; Port = $config.Port; KeyFile = $config.KeyFile
                SkipHostKeyCheck = $SkipHostKeyCheck
            }

            $uname = Invoke-SshCommand @sshParams -Command "uname -s"

            if ($uname.ExitCode -eq 0) {
                $remoteOS = switch -Regex (($uname.Output | Out-String).Trim()) {
                    'Linux'  { 'Linux' }
                    'Darwin' { 'macOS' }
                    default  { 'Linux' }
                }
            } else {
                # 嘗試 Windows
                $psTest = Invoke-SshCommand @sshParams -Command "powershell -NoProfile -Command `"if (Test-Path 'C:\Windows') { 'Windows' }`""
                if ($psTest.ExitCode -eq 0 -and ($psTest.Output | Out-String).Trim() -eq 'Windows') {
                    $remoteOS = 'Windows'
                } else {
                    Write-Host "✗ Failed to detect remote OS" -ForegroundColor Red
                    $exitCode = $EXIT_CONNECTION_FAILED; return
                }
            }
            Write-Host "  Detected: $remoteOS`n" -ForegroundColor Gray

            # 展開 GET 萬用字元並預取雜湊
            if ($getOps.Count -gt 0) {
                $getOps = Expand-GetOperation -Operations $getOps -SshHost $sshHost -Port $config.Port -KeyFile $config.KeyFile -RemoteOS $remoteOS
                Write-Host "► Pre-fetching GET hashes..." -ForegroundColor Yellow
                foreach ($op in $getOps) {
                    try {
                        $hashResult = Get-RemoteFileHash -SshHost $sshHost -Port $config.Port -KeyFile $config.KeyFile -RemotePath $op.RemotePath -RemoteOS $remoteOS
                        $remoteHashes[$op.RemotePath] = $hashResult.Hash
                        $remotePaths[$op.RemotePath] = $hashResult.AbsolutePath
                        Write-Host "  $($hashResult.AbsolutePath)" -ForegroundColor Gray
                    } catch {
                        Write-Host "  ✗ $($op.RemotePath): $_" -ForegroundColor Red
                        if (-not $ContinueOnError) { $exitCode = $EXIT_VERIFY_FAILED; return }
                    }
                }
                Write-Host ""
            }
        }

        # 執行傳輸
        Write-Host "► Transferring...`n" -ForegroundColor Yellow
        $sftpResult = Invoke-SftpExe -ScriptFile $ScriptFile -RemoteHost $config.Host -User $config.User -Port $config.Port -KeyFile $config.KeyFile -SkipHostKeyCheck:$SkipHostKeyCheck

        if ($sftpResult.ExitCode -ne 0) {
            Write-Host "`n✗ Transfer failed (code $($sftpResult.ExitCode))" -ForegroundColor Red
            $exitCode = $EXIT_TRANSFER_FAILED; return
        }
        Write-Host "`n  Done`n" -ForegroundColor Gray

        # 驗證
        if ($NoVerify) {
            Write-Host "► Skipped verification`n" -ForegroundColor Yellow
            Write-Host "───────────────────────────────────────────────────────────────" -ForegroundColor Cyan
            Write-Host "  Complete (no verify)" -ForegroundColor Green
            Write-Host "───────────────────────────────────────────────────────────────" -ForegroundColor Cyan
            return
        }

        Write-Host "► Verifying...`n" -ForegroundColor Yellow
        $passed = 0; $failed = 0

        foreach ($op in $putOps) {
            $r = Test-FileHash -LocalPath $op.LocalPath -RemotePath $op.RemotePath -SshHost $sshHost -Port $config.Port -KeyFile $config.KeyFile -RemoteOS $remoteOS -Action put
            $localPath = if ($r.LocalAbsPath) { $r.LocalAbsPath } else { $op.LocalPath }
            $remotePath = if ($r.RemoteAbsPath) { $r.RemoteAbsPath } else { $op.RemotePath }
            $hashL = if ($r.LocalHash) { $r.LocalHash.Substring(0,4) + ":" + $r.LocalHash.Substring(60,4) } else { "????:????" }
            $hashR = if ($r.RemoteHash) { $r.RemoteHash.Substring(0,4) + ":" + $r.RemoteHash.Substring(60,4) } else { "????:????" }
            if ($r.Success) { 
                Write-Host "  ✓ " -ForegroundColor Green -NoNewline
                Write-Host "[$hashL = $hashR]" -ForegroundColor DarkGray -NoNewline
                Write-Host " $localPath → $remotePath"
                $passed++ 
            }
            elseif ($r.Error) { 
                Write-Host "  ⚠ " -ForegroundColor Yellow -NoNewline
                Write-Host "[$hashL = $hashR] $localPath → $remotePath - $($r.Error)" -ForegroundColor Yellow
            }
            else { 
                Write-Host "  ✗ " -ForegroundColor Red -NoNewline
                Write-Host "[$hashL ≠ $hashR]" -ForegroundColor Red -NoNewline
                Write-Host " $localPath → $remotePath" -ForegroundColor Red
                $failed++
                if (-not $ContinueOnError) { $exitCode = $EXIT_VERIFY_FAILED; return } 
            }
        }

        foreach ($op in $getOps) {
            $r = Test-FileHash -LocalPath $op.LocalPath -RemotePath $op.RemotePath -ExpectedHash $remoteHashes[$op.RemotePath] -Action get
            $localPath = if ($r.LocalAbsPath) { $r.LocalAbsPath } else { $op.LocalPath }
            $remotePath = if ($remotePaths[$op.RemotePath]) { $remotePaths[$op.RemotePath] } else { $op.RemotePath }
            $hashL = if ($r.LocalHash) { $r.LocalHash.Substring(0,4) + ":" + $r.LocalHash.Substring(60,4) } else { "????:????" }
            $hashR = if ($r.RemoteHash) { $r.RemoteHash.Substring(0,4) + ":" + $r.RemoteHash.Substring(60,4) } else { "????:????" }
            if ($r.Success) { 
                Write-Host "  ✓ " -ForegroundColor Green -NoNewline
                Write-Host "[$hashR = $hashL]" -ForegroundColor DarkGray -NoNewline
                Write-Host " $localPath ← $remotePath"
                $passed++ 
            }
            elseif ($r.Error) { 
                Write-Host "  ⚠ " -ForegroundColor Yellow -NoNewline
                Write-Host "[$hashR = $hashL] $localPath ← $remotePath - $($r.Error)" -ForegroundColor Yellow
            }
            else { 
                Write-Host "  ✗ " -ForegroundColor Red -NoNewline
                Write-Host "[$hashR ≠ $hashL]" -ForegroundColor Red -NoNewline
                Write-Host " $localPath ← $remotePath" -ForegroundColor Red
                $failed++
                if (-not $ContinueOnError) { $exitCode = $EXIT_VERIFY_FAILED; return } 
            }
        }

        Write-Host "`n───────────────────────────────────────────────────────────────" -ForegroundColor Cyan
        Write-Host "  $passed passed, $failed failed" -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Red' })
        Write-Host "───────────────────────────────────────────────────────────────" -ForegroundColor Cyan
        if ($failed -gt 0) { $exitCode = $EXIT_VERIFY_FAILED }

    } finally {
        # 設定結束代碼（即使 return 提前結束也會執行）
        $global:LASTEXITCODE = $exitCode
        if ($exitCode -ne 0) {
            throw "vSFTP failed with exit code $exitCode"
        }
    }
}
