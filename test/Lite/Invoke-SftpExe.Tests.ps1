BeforeAll {
    $env:VSFTP_VARIANT = 'Lite'
    Import-Module "$PSScriptRoot/../../src/vSFTP.psd1" -Force
}

Describe "Invoke-SftpExe (Lite)" -Tag "Integration" {

    BeforeAll {
        $testDir = "$PSScriptRoot/../../test"
        $scriptDir = Join-Path $testDir "scripts"
        $localDir = Join-Path $testDir "local"

        # 確保測試腳本目錄存在
        if (-not (Test-Path $scriptDir)) {
            New-Item -ItemType Directory -Path $scriptDir | Out-Null
        }

        # 建立測試用 sftp 腳本
        $uploadScript = Join-Path $scriptDir "test-sftpexe.sftp"
        @(
            "lcd $localDir"
            "cd /home/testuser/upload"
            "put test.txt"
        ) | Set-Content $uploadScript

        # 確保測試檔案存在
        if (-not (Test-Path (Join-Path $localDir "test.txt"))) {
            "test content" | Set-Content (Join-Path $localDir "test.txt")
        }
    }

    Context "成功傳輸" {
        It "應該回傳輸出字串" {
            $result = InModuleScope vSFTP -Parameters @{
                Script = "$PSScriptRoot/../../test/scripts/test-sftpexe.sftp"
            } {
                param($Script)
                Invoke-SftpExe -ScriptFile $Script -RemoteHost localhost -User testuser -Port 2222 -KeyFile "$PSScriptRoot/../../secrets/id_ed25519" -SkipHostKeyCheck
            }
            $result | Should -Not -BeNullOrEmpty
        }
    }

    Context "失敗傳輸" {
        It "連線失敗時應該回傳 null" {
            $badScript = Join-Path ([System.IO.Path]::GetTempPath()) "bad-$(Get-Random).sftp"
            "put nonexistent.txt" | Set-Content $badScript

            try {
                $result = InModuleScope vSFTP -Parameters @{ Script = $badScript } {
                    param($Script)
                    Invoke-SftpExe -ScriptFile $Script -RemoteHost localhost -User testuser -Port 2222 -KeyFile "$PSScriptRoot/../../secrets/id_ed25519" -SkipHostKeyCheck -ErrorAction SilentlyContinue
                }
                $result | Should -BeNullOrEmpty
            } finally {
                Remove-Item $badScript -Force
            }
        }

        It "連線失敗加 ErrorAction Stop 應該拋出錯誤" {
            $badScript = Join-Path ([System.IO.Path]::GetTempPath()) "bad-$(Get-Random).sftp"
            "put nonexistent.txt" | Set-Content $badScript

            try {
                {
                    InModuleScope vSFTP -Parameters @{ Script = $badScript } {
                        param($Script)
                        Invoke-SftpExe -ScriptFile $Script -RemoteHost localhost -User testuser -Port 2222 -KeyFile "$PSScriptRoot/../../secrets/id_ed25519" -SkipHostKeyCheck -ErrorAction Stop
                    }
                } | Should -Throw "*SFTP transfer failed*"
            } finally {
                Remove-Item $badScript -Force
            }
        }
    }

    Context "參數驗證" {
        It "危險字元的主機名應該拋出錯誤" {
            {
                InModuleScope vSFTP {
                    Invoke-SftpExe -ScriptFile "test.sftp" -RemoteHost 'host;rm -rf /' -User testuser -KeyFile "key"
                }
            } | Should -Throw "*dangerous characters*"
        }

        It "危險字元的使用者名應該拋出錯誤" {
            {
                InModuleScope vSFTP {
                    Invoke-SftpExe -ScriptFile "test.sftp" -RemoteHost localhost -User 'user$(cmd)' -KeyFile "key"
                }
            } | Should -Throw "*dangerous characters*"
        }
    }
}
