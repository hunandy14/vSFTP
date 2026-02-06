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
    .PARAMETER Connection
        連線字串，格式：host=<host>;user=<user>[;key=<keypath>][;port=<port>]
        key 可選，省略時按 OpenSSH 順序自動搜尋 ~/.ssh/ 下的私鑰。
        port 可選，預設 22。若未指定則從環境變數 SFTP_CONNECTION 讀取。
    .EXAMPLE
        # 最簡形式（自動找金鑰）
        $env:SFTP_CONNECTION = "host=example.com;user=admin"
        Invoke-vSFTP -ScriptFile ./upload.sftp
    .EXAMPLE
        # 指定金鑰
        Invoke-vSFTP -ScriptFile ./upload.sftp -Connection "host=example.com;user=admin;key=/home/user/.ssh/id_rsa"
    .EXAMPLE
        # 指定 port
        Invoke-vSFTP -ScriptFile ./upload.sftp -Connection "host=example.com;user=admin;port=2222"
    .EXAMPLE
        # Windows 路徑
        Invoke-vSFTP -ScriptFile ./upload.sftp -Connection "host=example.com;user=admin;key=C:\Users\me\.ssh\id_rsa"
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
    $sshSession = $null
    $exitCode = $EXIT_SUCCESS

    try {
        Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
        Write-Host "  vSFTP - SFTP with Hash Verification" -ForegroundColor Cyan
        Write-Host "═══════════════════════════════════════════════════════════════`n" -ForegroundColor Cyan

        # 解析連線設定（參數優先，否則讀環境變數 SFTP_CONNECTION）
        $connStr = if ($Connection) { $Connection } else { $env:SFTP_CONNECTION }
        
        if (-not $connStr) {
            Write-Host "✗ SFTP_CONNECTION not set" -ForegroundColor Red
            Write-Host "  Format: host=<host>;user=<user>;key=<keypath>[;port=<port>]" -ForegroundColor Gray
            $exitCode = $EXIT_CONNECTION_FAILED; return
        }

        try {
            $config = ConvertFrom-ConnectionString -ConnectionString $connStr
        } catch {
            Write-Host "✗ $_" -ForegroundColor Red
            $exitCode = $EXIT_CONNECTION_FAILED; return
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
                ConnectionTimeout = 30; AcceptKey = $true
                KnownHost = New-SSHMemoryKnownHost
            }
            $sshSession = New-SSHSession @sshParams

            if (-not $sshSession) {
                Write-Host "✗ SSH failed" -ForegroundColor Red
                $exitCode = $EXIT_CONNECTION_FAILED; return
            }

            # 偵測 OS
            # 偵測遠端 OS：先嘗試 uname（Linux/macOS），失敗則嘗試 PowerShell（Windows）
            $uname = Invoke-SSHCommand -SessionId $sshSession.SessionId -Command "uname -s" -TimeOut 30
            if ($uname.ExitStatus -eq 0) {
                $remoteOS = switch -Regex ($uname.Output.Trim()) {
                    'Linux'  { 'Linux' }
                    'Darwin' { 'macOS' }
                    default  { 'Linux' }  # 其他 Unix-like 系統當作 Linux
                }
            } else {
                # uname 失敗，嘗試用 Test-Path 偵測 Windows（不執行命令，只檢查路徑）
                $psTest = Invoke-SSHCommand -SessionId $sshSession.SessionId -Command "powershell -NoProfile -Command `"if (Test-Path 'C:\Windows') { 'Windows' }`"" -TimeOut 30
                if ($psTest.ExitStatus -eq 0 -and $psTest.Output.Trim() -eq 'Windows') {
                    $remoteOS = 'Windows'
                } else {
                    Write-Host "✗ Failed to detect remote OS" -ForegroundColor Red
                    $exitCode = $EXIT_CONNECTION_FAILED; return
                }
            }
            Write-Host "  Connected ($remoteOS)`n" -ForegroundColor Gray

            # 展開 GET 萬用字元並預取雜湊
            if ($getOps.Count -gt 0) {
                $getOps = Expand-GetOperation -Operations $getOps -SessionId $sshSession.SessionId -RemoteOS $remoteOS
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
            $shortHash = if ($r.LocalHash) { $r.LocalHash.Substring(0, 16) } else { "?" }
            if ($r.Success) { Write-Host "  ✓ $($op.RemotePath) [$shortHash]" -ForegroundColor Green; $passed++ }
            elseif ($r.Error) { Write-Host "  ⚠ $($op.RemotePath) - $($r.Error)" -ForegroundColor Yellow }
            else { Write-Host "  ✗ $($op.RemotePath) MISMATCH [local:$($r.LocalHash.Substring(0,8)) != remote:$($r.RemoteHash.Substring(0,8))]" -ForegroundColor Red; $failed++; if (-not $ContinueOnError) { $exitCode = $EXIT_VERIFY_FAILED; return } }
        }

        foreach ($op in $getOps) {
            $r = Test-FileHash -LocalPath $op.LocalPath -RemotePath $op.RemotePath -ExpectedHash $remoteHashes[$op.RemotePath] -Action get
            $shortHash = if ($r.LocalHash) { $r.LocalHash.Substring(0, 16) } else { "?" }
            if ($r.Success) { Write-Host "  ✓ $($op.LocalPath) [$shortHash]" -ForegroundColor Green; $passed++ }
            elseif ($r.Error) { Write-Host "  ⚠ $($op.LocalPath) - $($r.Error)" -ForegroundColor Yellow }
            else { Write-Host "  ✗ $($op.LocalPath) MISMATCH [local:$($r.LocalHash.Substring(0,8)) != remote:$($r.RemoteHash.Substring(0,8))]" -ForegroundColor Red; $failed++; if (-not $ContinueOnError) { $exitCode = $EXIT_VERIFY_FAILED; return } }
        }

        Write-Host "`n───────────────────────────────────────────────────────────────" -ForegroundColor Cyan
        Write-Host "  $passed passed, $failed failed" -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Red' })
        Write-Host "───────────────────────────────────────────────────────────────" -ForegroundColor Cyan
        if ($failed -gt 0) { $exitCode = $EXIT_VERIFY_FAILED }

    } finally {
        if ($sshSession) { 
            try { Remove-SSHSession -SessionId $sshSession.SessionId | Out-Null } catch { }
        }
    }

    $global:LASTEXITCODE = $exitCode
    if ($exitCode -ne 0) {
        throw "vSFTP failed with exit code $exitCode"
    }
}
