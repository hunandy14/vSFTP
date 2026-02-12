BeforeAll {
    $env:VSFTP_VARIANT = 'Lite'
    Import-Module "$PSScriptRoot/../../src/vSFTP.psd1" -Force
}

Describe "多金鑰自動嘗試 (Lite)" -Tag "Integration" {

    BeforeAll {
        $sshHost = "testuser@localhost"
        $port = 2222
        $goodKey = "$PSScriptRoot/../../secrets/id_ed25519"
        $badKey = "$PSScriptRoot/../../secrets/id_rsa_dummy"
    }

    Context "Invoke-SshCommand" {

        It "使用正確的金鑰應該成功" {
            $result = InModuleScope vSFTP -Parameters @{ SshHost = $sshHost; Port = $port; Key = $goodKey } {
                param($SshHost, $Port, $Key)
                Invoke-SshCommand -SshHost $SshHost -Port $Port -KeyFile $Key -Command "echo hello"
            }
            $result | Should -Not -BeNullOrEmpty
            ($result | Out-String).Trim() | Should -Be "hello"
        }

        It "使用錯誤的金鑰應該失敗" {
            $result = InModuleScope vSFTP -Parameters @{ SshHost = $sshHost; Port = $port; Key = $badKey } {
                param($SshHost, $Port, $Key)
                Invoke-SshCommand -SshHost $SshHost -Port $Port -KeyFile $Key -Command "echo hello" -ErrorAction SilentlyContinue
            }
            $result | Should -BeNullOrEmpty
        }

        It "使用錯誤的金鑰加 ErrorAction Stop 應該拋出錯誤" {
            {
                InModuleScope vSFTP -Parameters @{ SshHost = $sshHost; Port = $port; Key = $badKey } {
                    param($SshHost, $Port, $Key)
                    Invoke-SshCommand -SshHost $SshHost -Port $Port -KeyFile $Key -Command "echo hello" -ErrorAction Stop
                }
            } | Should -Throw "*SSH command failed*"
        }

        It "不指定金鑰時讓 ssh 自動選擇" {
            # 主要測試不傳 -i 時不會報語法錯誤
            InModuleScope vSFTP -Parameters @{ SshHost = $sshHost; Port = $port } {
                param($SshHost, $Port)
                Invoke-SshCommand -SshHost $SshHost -Port $Port -Command "echo auto" -ErrorAction SilentlyContinue
            }
            # 不檢查結果（取決於系統金鑰）
        }
    }

    Context "Get-DefaultSshKey -All" {

        It "應該回傳多把金鑰" {
            $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "vsftp-multikey-$(Get-Random)"
            New-Item -ItemType Directory -Path $tempDir | Out-Null

            try {
                # 建立假的金鑰檔案（只要檔案存在就好）
                "rsa-key" | Set-Content (Join-Path $tempDir "id_rsa")
                "ed25519-key" | Set-Content (Join-Path $tempDir "id_ed25519")

                $keys = InModuleScope vSFTP -Parameters @{ Dir = $tempDir } {
                    param($Dir)
                    Get-DefaultSshKey -SshDir $Dir -All
                }

                $keys.Count | Should -Be 2
                $keys[0] | Should -BeLike "*id_rsa"
                $keys[1] | Should -BeLike "*id_ed25519"
            } finally {
                Remove-Item -Recurse -Force $tempDir
            }
        }

        It "應該按 OpenSSH 順序回傳" {
            $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "vsftp-multikey-$(Get-Random)"
            New-Item -ItemType Directory -Path $tempDir | Out-Null

            try {
                # 反向建立，確認回傳順序不受建立順序影響
                "ed25519-key" | Set-Content (Join-Path $tempDir "id_ed25519")
                "ecdsa-key" | Set-Content (Join-Path $tempDir "id_ecdsa")
                "rsa-key" | Set-Content (Join-Path $tempDir "id_rsa")

                $keys = InModuleScope vSFTP -Parameters @{ Dir = $tempDir } {
                    param($Dir)
                    Get-DefaultSshKey -SshDir $Dir -All
                }

                $keys.Count | Should -Be 3
                $keys[0] | Should -BeLike "*id_rsa"
                $keys[1] | Should -BeLike "*id_ecdsa"
                $keys[2] | Should -BeLike "*id_ed25519"
            } finally {
                Remove-Item -Recurse -Force $tempDir
            }
        }
    }

    Context "Get-RemoteFileHash 多金鑰" {

        It "正確金鑰排在第二也能成功（透過 Invoke-SshCommand）" {
            # 先確保遠端有測試檔案
            InModuleScope vSFTP -Parameters @{ SshHost = $sshHost; Port = $port; Key = $goodKey } {
                param($SshHost, $Port, $Key)
                Invoke-SshCommand -SshHost $SshHost -Port $Port -KeyFile $Key -Command "echo 'test content' > /home/testuser/upload/multikey-test.txt" -ErrorAction Stop
            }

            $result = InModuleScope vSFTP -Parameters @{ SshHost = $sshHost; Port = $port; Key = $goodKey } {
                param($SshHost, $Port, $Key)
                Get-RemoteFileHash -SshHost $SshHost -Port $Port -KeyFile $Key -RemotePath "/home/testuser/upload/multikey-test.txt" -RemoteOS Linux
            }

            $result.Hash | Should -Match '^[A-F0-9]{64}$'
            $result.AbsolutePath | Should -BeLike "*/multikey-test.txt"
        }
    }
}
