BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot "../src/vSFTP.psd1"
    Import-Module $ModulePath -Force
}

Describe "vSFTP 模組" {
    Context "模組載入" {
        It "應該成功匯入模組" {
            Get-Module vSFTP | Should -Not -BeNullOrEmpty
        }

        It "應該匯出 Invoke-vSFTP 函數" {
            Get-Command Invoke-vSFTP -Module vSFTP | Should -Not -BeNullOrEmpty
        }

        It "應該包含所有必要的私有函數" {
            InModuleScope vSFTP {
                Get-Command ConvertFrom-SftpScript | Should -Not -BeNullOrEmpty
                Get-Command Get-RemoteFileHash | Should -Not -BeNullOrEmpty
                Get-Command Test-FileHash | Should -Not -BeNullOrEmpty
                Get-Command Expand-GetOperation | Should -Not -BeNullOrEmpty
                Get-Command Invoke-SftpExe | Should -Not -BeNullOrEmpty
            }
        }
    }
}

Describe "Get-RemoteFileHash" -Tag "Integration" {
    BeforeAll {
        $script:ServerRunning = $false
        $container = docker ps --filter "name=vsftp-test-server" --format "{{.Names}}" 2>$null
        $script:ServerRunning = ($container -eq "vsftp-test-server")
        
        if ($script:ServerRunning) {
            $script:Session = New-SSHSession -ComputerName localhost -Port 2222 `
                -Credential (New-Object PSCredential("testuser", (New-Object SecureString))) `
                -KeyFile "secrets/id_ed25519" -AcceptKey -KnownHost (New-SSHMemoryKnownHost)
        }
    }

    AfterAll {
        if ($script:Session) {
            Remove-SSHSession -SessionId $script:Session.SessionId | Out-Null
        }
    }

    It "應該取得 Linux 檔案的 SHA256 雜湊" {
        if (-not $script:ServerRunning) {
            Set-ItResult -Skipped -Because "測試伺服器未運行"
            return
        }

        InModuleScope vSFTP -Parameters @{ SessionId = $script:Session.SessionId } {
            $hash = Get-RemoteFileHash -SessionId $SessionId -RemotePath "/home/testuser/upload/remote-file.txt" -RemoteOS "Linux"
            $hash | Should -Match "^[A-F0-9]{64}$"
        }
    }

    It "應該正確處理 Base64 編碼路徑" {
        if (-not $script:ServerRunning) {
            Set-ItResult -Skipped -Because "測試伺服器未運行"
            return
        }

        InModuleScope vSFTP -Parameters @{ SessionId = $script:Session.SessionId } {
            $hash = Get-RemoteFileHash -SessionId $SessionId -RemotePath "/home/testuser/upload/access.log" -RemoteOS "Linux"
            $hash | Should -Match "^[A-F0-9]{64}$"
            $hash.Length | Should -Be 64
        }
    }

    It "應該在檔案不存在時拋出錯誤" {
        if (-not $script:ServerRunning) {
            Set-ItResult -Skipped -Because "測試伺服器未運行"
            return
        }

        InModuleScope vSFTP -Parameters @{ SessionId = $script:Session.SessionId } {
            { Get-RemoteFileHash -SessionId $SessionId -RemotePath "/nonexistent/file.txt" -RemoteOS "Linux" } | Should -Throw
        }
    }
}

Describe "Expand-GetOperation" -Tag "Integration" {
    BeforeAll {
        $script:ServerRunning = $false
        $container = docker ps --filter "name=vsftp-test-server" --format "{{.Names}}" 2>$null
        $script:ServerRunning = ($container -eq "vsftp-test-server")
        
        if ($script:ServerRunning) {
            $script:Session = New-SSHSession -ComputerName localhost -Port 2222 `
                -Credential (New-Object PSCredential("testuser", (New-Object SecureString))) `
                -KeyFile "secrets/id_ed25519" -AcceptKey -KnownHost (New-SSHMemoryKnownHost)
        }
    }

    AfterAll {
        if ($script:Session) {
            Remove-SSHSession -SessionId $script:Session.SessionId | Out-Null
        }
    }

    It "應該展開遠端萬用字元" {
        if (-not $script:ServerRunning) {
            Set-ItResult -Skipped -Because "測試伺服器未運行"
            return
        }

        InModuleScope vSFTP -Parameters @{ SessionId = $script:Session.SessionId } {
            $ops = @([PSCustomObject]@{
                Action      = 'get'
                LocalPath   = '/tmp/*.log'
                RemotePath  = '/home/testuser/upload/*.log'
                Line        = 1
                HasWildcard = $true
            })

            $result = Expand-GetOperation -Operations $ops -SessionId $SessionId -RemoteOS Linux

            $result.Count | Should -BeGreaterOrEqual 1
            $result | ForEach-Object { $_.HasWildcard | Should -Be $false }
        }
    }

    It "應該拒絕含危險字元的模式（分號）" {
        if (-not $script:ServerRunning) {
            Set-ItResult -Skipped -Because "測試伺服器未運行"
            return
        }

        InModuleScope vSFTP -Parameters @{ SessionId = $script:Session.SessionId } {
            $ops = @([PSCustomObject]@{
                Action      = 'get'
                LocalPath   = '/tmp/test'
                RemotePath  = '/home/testuser/upload/;rm -rf /'
                Line        = 1
                HasWildcard = $true
            })

            { Expand-GetOperation -Operations $ops -SessionId $SessionId -RemoteOS Linux } | Should -Throw "*dangerous*"
        }
    }

    It "應該拒絕含單引號的模式" {
        if (-not $script:ServerRunning) {
            Set-ItResult -Skipped -Because "測試伺服器未運行"
            return
        }

        InModuleScope vSFTP -Parameters @{ SessionId = $script:Session.SessionId } {
            $ops = @([PSCustomObject]@{
                Action      = 'get'
                LocalPath   = '/tmp/test'
                RemotePath  = "/tmp/file'*.log"
                Line        = 1
                HasWildcard = $true
            })

            { Expand-GetOperation -Operations $ops -SessionId $SessionId -RemoteOS Linux } | Should -Throw "*dangerous*"
        }
    }

    It "應該拒絕含雙引號的模式" {
        if (-not $script:ServerRunning) {
            Set-ItResult -Skipped -Because "測試伺服器未運行"
            return
        }

        InModuleScope vSFTP -Parameters @{ SessionId = $script:Session.SessionId } {
            $ops = @([PSCustomObject]@{
                Action      = 'get'
                LocalPath   = '/tmp/test'
                RemotePath  = '/tmp/file"*.log'
                Line        = 1
                HasWildcard = $true
            })

            { Expand-GetOperation -Operations $ops -SessionId $SessionId -RemoteOS Linux } | Should -Throw "*dangerous*"
        }
    }

    It "應該拒絕含換行符的模式" {
        if (-not $script:ServerRunning) {
            Set-ItResult -Skipped -Because "測試伺服器未運行"
            return
        }

        InModuleScope vSFTP -Parameters @{ SessionId = $script:Session.SessionId } {
            $ops = @([PSCustomObject]@{
                Action      = 'get'
                LocalPath   = '/tmp/test'
                RemotePath  = "/tmp/*.log`n;rm -rf /"
                Line        = 1
                HasWildcard = $true
            })

            { Expand-GetOperation -Operations $ops -SessionId $SessionId -RemoteOS Linux } | Should -Throw "*dangerous*"
        }
    }

    It "應該保留非萬用字元操作" {
        if (-not $script:ServerRunning) {
            Set-ItResult -Skipped -Because "測試伺服器未運行"
            return
        }

        InModuleScope vSFTP -Parameters @{ SessionId = $script:Session.SessionId } {
            $ops = @(
                [PSCustomObject]@{
                    Action      = 'get'
                    LocalPath   = '/tmp/test.txt'
                    RemotePath  = '/home/testuser/upload/remote-file.txt'
                    Line        = 1
                    HasWildcard = $false
                }
            )

            $result = Expand-GetOperation -Operations $ops -SessionId $SessionId -RemoteOS Linux

            $result.Count | Should -Be 1
            $result[0].RemotePath | Should -Be '/home/testuser/upload/remote-file.txt'
        }
    }
}

Describe "Test-FileHash" {
    BeforeAll {
        $TempDir = Join-Path $PSScriptRoot "temp"
        if (-not (Test-Path $TempDir)) {
            New-Item -ItemType Directory -Path $TempDir | Out-Null
        }
    }

    AfterAll {
        if (Test-Path $TempDir) {
            Remove-Item $TempDir -Recurse -Force
        }
    }

    It "GET 模式：應該驗證本地檔案與預期雜湊相符" {
        InModuleScope vSFTP -Parameters @{ TempDir = $TempDir } {
            $testFile = Join-Path $TempDir "hash-test.txt"
            "test content" | Set-Content $testFile
            $expectedHash = (Get-FileHash $testFile -Algorithm SHA256).Hash

            $result = Test-FileHash -LocalPath $testFile -RemotePath "/dummy" -ExpectedHash $expectedHash -Action get

            $result.Success | Should -Be $true
            $result.LocalHash | Should -Be $expectedHash
        }
    }

    It "GET 模式：雜湊不符時應該失敗" {
        InModuleScope vSFTP -Parameters @{ TempDir = $TempDir } {
            $testFile = Join-Path $TempDir "hash-test2.txt"
            "test content" | Set-Content $testFile
            $wrongHash = "A" * 64

            $result = Test-FileHash -LocalPath $testFile -RemotePath "/dummy" -ExpectedHash $wrongHash -Action get

            $result.Success | Should -Be $false
        }
    }

    It "檔案不存在時應該回傳錯誤" {
        InModuleScope vSFTP {
            $result = Test-FileHash -LocalPath "/nonexistent/file.txt" -RemotePath "/dummy" -ExpectedHash "ABC" -Action get

            $result.Success | Should -Be $false
            $result.Error | Should -Not -BeNullOrEmpty
        }
    }

    It "應該正確計算本地檔案雜湊" {
        InModuleScope vSFTP -Parameters @{ TempDir = $TempDir } {
            $testFile = Join-Path $TempDir "hash-test3.txt"
            "test content for hash" | Set-Content $testFile
            $expectedHash = (Get-FileHash $testFile -Algorithm SHA256).Hash

            $result = Test-FileHash -LocalPath $testFile -RemotePath "/dummy" -ExpectedHash $expectedHash -Action get

            $result.LocalHash | Should -Be $expectedHash
            $result.LocalHash.Length | Should -Be 64
        }
    }

    It "GET 模式：沒有預期雜湊時應該回傳錯誤" {
        InModuleScope vSFTP -Parameters @{ TempDir = $TempDir } {
            $testFile = Join-Path $TempDir "hash-test4.txt"
            "test" | Set-Content $testFile

            $result = Test-FileHash -LocalPath $testFile -RemotePath "/dummy" -Action get

            $result.Success | Should -Be $false
            $result.Error | Should -Match "No pre-transfer hash"
        }
    }
}

Describe "Invoke-vSFTP 連線字串" {
    It "應該在缺少 SFTP_CONNECTION 時顯示錯誤" {
        $original = $env:SFTP_CONNECTION
        
        try {
            $env:SFTP_CONNECTION = $null
            
            # 使用 6>&1 捕獲所有輸出
            $output = & { Invoke-vSFTP -ScriptFile "test/scripts/test-upload.sftp" } 6>&1 2>&1 | Out-String
            $output | Should -Match "SFTP_CONNECTION not set"
        } finally {
            $env:SFTP_CONNECTION = $original
        }
    }

    It "應該在缺少必要欄位時顯示錯誤" {
        $original = $env:SFTP_CONNECTION
        
        try {
            $env:SFTP_CONNECTION = "host=localhost"  # 缺少 user 和 key
            
            $output = & { Invoke-vSFTP -ScriptFile "test/scripts/test-upload.sftp" } 6>&1 2>&1 | Out-String
            $output | Should -Match "Missing required fields"
        } finally {
            $env:SFTP_CONNECTION = $original
        }
    }

    It "應該正確解析完整連線字串（含 port）" {
        $original = $env:SFTP_CONNECTION
        
        try {
            # 使用不存在的主機測試解析（會在連線時失敗，但能驗證解析正確）
            $env:SFTP_CONNECTION = "host=nonexistent.host;port=2222;user=testuser;key=secrets/id_ed25519"
            
            $output = & { Invoke-vSFTP -ScriptFile "test/scripts/test-upload.sftp" } 6>&1 2>&1 | Out-String
            $output | Should -Match "testuser@nonexistent.host:2222"
        } finally {
            $env:SFTP_CONNECTION = $original
        }
    }
}

Describe "Invoke-vSFTP 整合測試" -Tag "Integration" {
    BeforeAll {
        $script:ServerRunning = $false
        $container = docker ps --filter "name=vsftp-test-server" --format "{{.Names}}" 2>$null
        $script:ServerRunning = ($container -eq "vsftp-test-server")
        
        if ($script:ServerRunning) {
            $env:SFTP_CONNECTION = "host=localhost;port=2222;user=testuser;key=secrets/id_ed25519"
        }
    }

    It "應該成功執行 PUT 操作" {
        if (-not $script:ServerRunning) {
            Set-ItResult -Skipped -Because "測試伺服器未運行"
            return
        }

        $output = & { Invoke-vSFTP -ScriptFile "test/scripts/test-upload.sftp" } 6>&1 2>&1 | Out-String
        $output | Should -Match "1 passed, 0 failed"
    }

    It "應該成功執行 GET 操作" {
        if (-not $script:ServerRunning) {
            Set-ItResult -Skipped -Because "測試伺服器未運行"
            return
        }

        $output = & { Invoke-vSFTP -ScriptFile "test/scripts/test-download.sftp" } 6>&1 2>&1 | Out-String
        $output | Should -Match "1 passed, 0 failed"
    }

    It "應該成功展開萬用字元並執行 GET" {
        if (-not $script:ServerRunning) {
            Set-ItResult -Skipped -Because "測試伺服器未運行"
            return
        }

        $output = & { Invoke-vSFTP -ScriptFile "test/scripts/test-wildcard.sftp" } 6>&1 2>&1 | Out-String
        $output | Should -Match "3 passed, 0 failed"
    }

    It "DryRun 模式應該只解析不執行" {
        if (-not $script:ServerRunning) {
            Set-ItResult -Skipped -Because "測試伺服器未運行"
            return
        }

        $output = & { Invoke-vSFTP -ScriptFile "test/scripts/test-upload.sftp" -DryRun } 6>&1 2>&1 | Out-String
        $output | Should -Match "Dry Run"
        $output | Should -Not -Match "Transferring"
    }
}
