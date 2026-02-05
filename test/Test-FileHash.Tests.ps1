BeforeAll {
    Import-Module "$PSScriptRoot/../src/vSFTP.psd1" -Force
}

Describe "Test-FileHash" -Tag "Unit" {
    BeforeAll {
        $script:TempDir = Join-Path $PSScriptRoot "temp"
        if (-not (Test-Path $script:TempDir)) {
            New-Item -ItemType Directory -Path $script:TempDir | Out-Null
        }
    }

    AfterAll {
        if (Test-Path $script:TempDir) {
            Remove-Item $script:TempDir -Recurse -Force
        }
    }

    It "GET 模式：應該驗證本地檔案與預期雜湊相符" {
        InModuleScope vSFTP -Parameters @{ TempDir = $script:TempDir } {
            $testFile = Join-Path $TempDir "hash-test.txt"
            "test content" | Set-Content $testFile
            $expectedHash = (Get-FileHash $testFile -Algorithm SHA256).Hash

            $result = Test-FileHash -LocalPath $testFile -RemotePath "/dummy" -ExpectedHash $expectedHash -Action get

            $result.Success | Should -Be $true
            $result.LocalHash | Should -Be $expectedHash
        }
    }

    It "GET 模式：雜湊不符時應該失敗" {
        InModuleScope vSFTP -Parameters @{ TempDir = $script:TempDir } {
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
        InModuleScope vSFTP -Parameters @{ TempDir = $script:TempDir } {
            $testFile = Join-Path $TempDir "hash-test3.txt"
            "test content for hash" | Set-Content $testFile
            $expectedHash = (Get-FileHash $testFile -Algorithm SHA256).Hash

            $result = Test-FileHash -LocalPath $testFile -RemotePath "/dummy" -ExpectedHash $expectedHash -Action get

            $result.LocalHash | Should -Be $expectedHash
            $result.LocalHash.Length | Should -Be 64
        }
    }

    It "GET 模式：沒有預期雜湊時應該回傳錯誤" {
        InModuleScope vSFTP -Parameters @{ TempDir = $script:TempDir } {
            $testFile = Join-Path $TempDir "hash-test4.txt"
            "test" | Set-Content $testFile

            $result = Test-FileHash -LocalPath $testFile -RemotePath "/dummy" -Action get

            $result.Success | Should -Be $false
            $result.Error | Should -Match "No pre-transfer hash"
        }
    }
}
