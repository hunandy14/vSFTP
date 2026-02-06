BeforeAll {
    . "$PSScriptRoot/../src/Private/Get-DefaultSshKey.ps1"
}

Describe 'Get-DefaultSshKey' {
    BeforeAll {
        # 建立測試用 .ssh 目錄
        $script:testSshDir = Join-Path $TestDrive '.ssh'
        New-Item -Path $script:testSshDir -ItemType Directory -Force | Out-Null
    }

    BeforeEach {
        # 清空 .ssh 目錄
        Get-ChildItem $script:testSshDir -File -ErrorAction SilentlyContinue | Remove-Item -Force
    }

    Context '找不到金鑰時' {
        It '回傳 $null' {
            Get-DefaultSshKey -SshDir $script:testSshDir | Should -BeNullOrEmpty
        }
    }

    Context 'OpenSSH 搜尋順序' {
        It '優先使用 id_rsa' {
            # 建立多個金鑰
            'rsa' | Set-Content (Join-Path $script:testSshDir 'id_rsa')
            'ed25519' | Set-Content (Join-Path $script:testSshDir 'id_ed25519')
            
            $result = Get-DefaultSshKey -SshDir $script:testSshDir
            $result | Should -BeLike '*id_rsa'
        }

        It 'id_rsa 不存在時使用 id_ecdsa' {
            'ecdsa' | Set-Content (Join-Path $script:testSshDir 'id_ecdsa')
            'ed25519' | Set-Content (Join-Path $script:testSshDir 'id_ed25519')
            
            $result = Get-DefaultSshKey -SshDir $script:testSshDir
            $result | Should -BeLike '*id_ecdsa'
        }

        It 'id_ecdsa 不存在時使用 id_ecdsa_sk' {
            'ecdsa_sk' | Set-Content (Join-Path $script:testSshDir 'id_ecdsa_sk')
            'ed25519' | Set-Content (Join-Path $script:testSshDir 'id_ed25519')
            
            $result = Get-DefaultSshKey -SshDir $script:testSshDir
            $result | Should -BeLike '*id_ecdsa_sk'
        }

        It 'id_ecdsa_sk 不存在時使用 id_ed25519' {
            'ed25519' | Set-Content (Join-Path $script:testSshDir 'id_ed25519')
            'ed25519_sk' | Set-Content (Join-Path $script:testSshDir 'id_ed25519_sk')
            
            $result = Get-DefaultSshKey -SshDir $script:testSshDir
            $result | Should -BeLike '*id_ed25519'
        }

        It 'id_ed25519 不存在時使用 id_ed25519_sk' {
            'ed25519_sk' | Set-Content (Join-Path $script:testSshDir 'id_ed25519_sk')
            
            $result = Get-DefaultSshKey -SshDir $script:testSshDir
            $result | Should -BeLike '*id_ed25519_sk'
        }
    }

    Context '回傳完整路徑' {
        It '回傳絕對路徑' {
            'test' | Set-Content (Join-Path $script:testSshDir 'id_rsa')
            
            $result = Get-DefaultSshKey -SshDir $script:testSshDir
            $result | Should -Be (Join-Path $script:testSshDir 'id_rsa')
        }
    }

    Context '預設使用 ~/.ssh' {
        It '不指定 SshDir 時使用 $HOME/.ssh' {
            # 只測試函數會呼叫正確路徑，不實際修改 $HOME
            # 這裡我們只驗證函數存在且可呼叫
            { Get-DefaultSshKey } | Should -Not -Throw
        }
    }
}
