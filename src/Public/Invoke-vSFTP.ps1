function Invoke-vSFTP {
    <#
    .SYNOPSIS
        執行帶有 SHA256 雜湊驗證的 SFTP 批次腳本。
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
        [Parameter(Mandatory, Position = 0)][string]$ScriptFile,
        [switch]$NoVerify,
        [switch]$ContinueOnError,
        [switch]$DryRun,
        [switch]$SkipHostKeyCheck
    )

    $EXIT_SUCCESS = 0; $EXIT_VERIFY_FAILED = 1; $EXIT_TRANSFER_FAILED = 2; $EXIT_CONNECTION_FAILED = 3
    $sshSession = $null
    $exitCode = $EXIT_SUCCESS

    try {
        Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
        Write-Host "  vSFTP - SFTP with Hash Verification" -ForegroundColor Cyan
        Write-Host "═══════════════════════════════════════════════════════════════`n" -ForegroundColor Cyan

        # 驗證環境變數
        $required = @('SFTP_HOST', 'SFTP_USER', 'SFTP_KEYFILE')
        $missing = $required | Where-Object { -not (Get-Item "env:$_" -ErrorAction SilentlyContinue) }
        if ($missing) {
            $missing | ForEach-Object { Write-Host "✗ $_ not set" -ForegroundColor Red }
            $exitCode = $EXIT_CONNECTION_FAILED; return
        }

        $config = @{
            Host = $env:SFTP_HOST; User = $env:SFTP_USER; KeyFile = $env:SFTP_KEYFILE
            Port = if ($env:SFTP_PORT) { [int]$env:SFTP_PORT } else { 22 }
        }
        Write-Host "Host: $($config.User)@$($config.Host):$($config.Port)" -ForegroundColor Gray
        Write-Host "Key:  $($config.KeyFile)`n" -ForegroundColor Gray

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

        # SSH 連線（驗證模式）
        $remoteOS = $null; $remoteHashes = @{}

        if (-not $NoVerify) {
            Write-Host "► Connecting SSH..." -ForegroundColor Yellow
            $sshParams = @{
                ComputerName = $config.Host; Port = $config.Port; KeyFile = $config.KeyFile
                Credential = New-Object PSCredential($config.User, (New-Object SecureString))
                ConnectionTimeout = 30; AcceptKey = $true; Force = $true
            }
            $sshSession = New-SSHSession @sshParams -WarningAction SilentlyContinue

            if (-not $sshSession) {
                Write-Host "✗ SSH failed" -ForegroundColor Red
                $exitCode = $EXIT_CONNECTION_FAILED; return
            }

            # 偵測 OS
            $uname = Invoke-SSHCommand -SessionId $sshSession.SessionId -Command "uname -s" -TimeOut 30
            $remoteOS = if ($uname.ExitStatus -eq 0) {
                switch -Regex ($uname.Output.Trim()) { 'Linux' { 'Linux' } 'Darwin' { 'macOS' } default { 'Linux' } }
            } else { 'Windows' }
            Write-Host "  Connected ($remoteOS)`n" -ForegroundColor Gray

            # 展開 GET 萬用字元並預取雜湊
            if ($getOps.Count -gt 0) {
                $getOps = Expand-GetOperation -Operations $getOps -SessionId $sshSession.SessionId
                Write-Host "► Pre-fetching GET hashes..." -ForegroundColor Yellow
                foreach ($op in $getOps) {
                    try {
                        $remoteHashes[$op.RemotePath] = Get-RemoteFileHash -SessionId $sshSession.SessionId -RemotePath $op.RemotePath -RemoteOS $remoteOS
                        Write-Host "  $($op.RemotePath)" -ForegroundColor Gray
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
            $r = Test-FileHash -LocalPath $op.LocalPath -RemotePath $op.RemotePath -SessionId $sshSession.SessionId -RemoteOS $remoteOS -Action put
            if ($r.Success) { Write-Host "  ✓ $($op.RemotePath)" -ForegroundColor Green; $passed++ }
            elseif ($r.Error) { Write-Host "  ⚠ $($op.RemotePath) - $($r.Error)" -ForegroundColor Yellow }
            else { Write-Host "  ✗ $($op.RemotePath) MISMATCH" -ForegroundColor Red; $failed++; if (-not $ContinueOnError) { $exitCode = $EXIT_VERIFY_FAILED; return } }
        }

        foreach ($op in $getOps) {
            $r = Test-FileHash -LocalPath $op.LocalPath -RemotePath $op.RemotePath -ExpectedHash $remoteHashes[$op.RemotePath] -Action get
            if ($r.Success) { Write-Host "  ✓ $($op.LocalPath)" -ForegroundColor Green; $passed++ }
            elseif ($r.Error) { Write-Host "  ⚠ $($op.LocalPath) - $($r.Error)" -ForegroundColor Yellow }
            else { Write-Host "  ✗ $($op.LocalPath) MISMATCH" -ForegroundColor Red; $failed++; if (-not $ContinueOnError) { $exitCode = $EXIT_VERIFY_FAILED; return } }
        }

        Write-Host "`n───────────────────────────────────────────────────────────────" -ForegroundColor Cyan
        Write-Host "  $passed passed, $failed failed" -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Red' })
        Write-Host "───────────────────────────────────────────────────────────────" -ForegroundColor Cyan
        if ($failed -gt 0) { $exitCode = $EXIT_VERIFY_FAILED }

    } finally {
        if ($sshSession) { Remove-SSHSession -SessionId $sshSession.SessionId -ErrorAction SilentlyContinue | Out-Null }
    }

    $global:LASTEXITCODE = $exitCode
    if ($exitCode -ne 0) {
        throw "vSFTP failed with exit code $exitCode"
    }
}
