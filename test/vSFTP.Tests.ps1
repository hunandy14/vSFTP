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
    }
}

Describe "Get-RemoteFileHash" -Tag "Integration" {
    BeforeAll {
        # 檢查測試伺服器是否運行中
        $script:TestServerRunning = $false
        try {
            $container = docker ps --filter "name=vsftp-test-server" --format "{{.Names}}" 2>$null
            $script:TestServerRunning = ($container -eq "vsftp-test-server")
        } catch { }
    }

    It "應該取得 Linux 檔案的 SHA256 雜湊" -Skip:(-not $script:TestServerRunning) {
        InModuleScope vSFTP {
            $session = New-SSHSession -ComputerName localhost -Port 2222 `
                -Credential (New-Object PSCredential("testuser", (New-Object SecureString))) `
                -KeyFile "SECRET/id_ed25519" -AcceptKey -Force

            try {
                $hash = Get-RemoteFileHash -SessionId $session.SessionId -RemotePath "/home/testuser/upload/remote-file.txt" -RemoteOS "Linux"
                $hash | Should -Match "^[A-F0-9]{64}$"
            } finally {
                Remove-SSHSession -SessionId $session.SessionId | Out-Null
            }
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
}
