BeforeAll {
    Import-Module "$PSScriptRoot/../../src/vSFTP.psd1" -Force
}

Describe "Exit Code 測試" -Tag "Unit" {
    BeforeAll {
        $script:OriginalConnection = $env:SFTP_CONNECTION
    }

    AfterEach {
        $env:SFTP_CONNECTION = $script:OriginalConnection
        $global:LASTEXITCODE = 0
    }

    Context "連線失敗 (EXIT_CONNECTION_FAILED = 3)" {
        It "缺少 SFTP_CONNECTION 應該拋出錯誤並返回 exit code 3" {
            $env:SFTP_CONNECTION = $null
            
            { Invoke-vSFTP -ScriptFile "test/scripts/test-upload.sftp" 6>$null } | Should -Throw "*exit code 3*"
            $global:LASTEXITCODE | Should -Be 3
        }

        It "缺少必要欄位（User）應該拋出錯誤並返回 exit code 3" {
            $env:SFTP_CONNECTION = "HostName=localhost"
            
            { Invoke-vSFTP -ScriptFile "test/scripts/test-upload.sftp" 6>$null } | Should -Throw "*exit code 3*"
            $global:LASTEXITCODE | Should -Be 3
        }

        It "缺少必要欄位（HostName）應該拋出錯誤並返回 exit code 3" {
            $env:SFTP_CONNECTION = "User=testuser"
            
            { Invoke-vSFTP -ScriptFile "test/scripts/test-upload.sftp" 6>$null } | Should -Throw "*exit code 3*"
            $global:LASTEXITCODE | Should -Be 3
        }
    }

    Context "傳輸失敗 (EXIT_TRANSFER_FAILED = 2)" {
        It "腳本檔案不存在應該拋出錯誤並返回 exit code 2" {
            $env:SFTP_CONNECTION = "HostName=localhost;User=test;IdentityFile=/tmp/fake_key"
            
            { Invoke-vSFTP -ScriptFile "/nonexistent/script.sftp" 6>$null } | Should -Throw "*exit code 2*"
            $global:LASTEXITCODE | Should -Be 2
        }

        It "空腳本（無操作）應該拋出錯誤並返回 exit code 2" {
            $env:SFTP_CONNECTION = "HostName=localhost;User=test;IdentityFile=/tmp/fake_key"
            $emptyScript = Join-Path $PSScriptRoot "temp-empty.sftp"
            
            try {
                "# empty script" | Set-Content $emptyScript
                { Invoke-vSFTP -ScriptFile $emptyScript 6>$null } | Should -Throw "*exit code 2*"
                $global:LASTEXITCODE | Should -Be 2
            } finally {
                Remove-Item $emptyScript -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe "Exit Code 整合測試" -Tag "Integration" {
    BeforeAll {
        $script:ServerRunning = $false
        $container = docker ps --filter "name=vsftp-test-server" --format "{{.Names}}" 2>$null
        $script:ServerRunning = ($container -eq "vsftp-test-server")
        
        if ($script:ServerRunning) {
            $env:SFTP_CONNECTION = "HostName=localhost;Port=2222;User=testuser;IdentityFile=secrets/id_ed25519"
        }
    }

    Context "驗證失敗 (EXIT_VERIFY_FAILED = 1)" {
        It "上傳不存在的本地檔案應該拋出錯誤" {
            if (-not $script:ServerRunning) {
                Set-ItResult -Skipped -Because "測試伺服器未運行"
                return
            }

            $badScript = Join-Path $PSScriptRoot "temp-bad-upload.sftp"
            try {
                @"
lcd /nonexistent/path
put nonexistent.txt
"@ | Set-Content $badScript

                { Invoke-vSFTP -ScriptFile $badScript 6>$null } | Should -Throw "*exit code*"
                # 解析階段就會失敗，屬於 TRANSFER_FAILED
                $global:LASTEXITCODE | Should -BeIn @(1, 2)
            } finally {
                Remove-Item $badScript -ErrorAction SilentlyContinue
            }
        }
    }

    Context "成功 (EXIT_SUCCESS = 0)" {
        It "成功的 PUT 操作應該返回 0" {
            if (-not $script:ServerRunning) {
                Set-ItResult -Skipped -Because "測試伺服器未運行"
                return
            }

            { Invoke-vSFTP -ScriptFile "test/scripts/test-upload.sftp" } | Should -Not -Throw
            $global:LASTEXITCODE | Should -Be 0
        }

        It "DryRun 模式應該返回 0" {
            if (-not $script:ServerRunning) {
                Set-ItResult -Skipped -Because "測試伺服器未運行"
                return
            }

            { Invoke-vSFTP -ScriptFile "test/scripts/test-upload.sftp" -DryRun } | Should -Not -Throw
            $global:LASTEXITCODE | Should -Be 0
        }

        It "NoVerify 模式成功傳輸應該返回 0" {
            if (-not $script:ServerRunning) {
                Set-ItResult -Skipped -Because "測試伺服器未運行"
                return
            }

            { Invoke-vSFTP -ScriptFile "test/scripts/test-upload.sftp" -NoVerify } | Should -Not -Throw
            $global:LASTEXITCODE | Should -Be 0
        }
    }
}
