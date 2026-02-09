BeforeAll {
    $env:VSFTP_VARIANT = 'Lite'
    Import-Module "$PSScriptRoot/../../src/vSFTP.psd1" -Force
}

AfterAll {
    Remove-Item Env:VSFTP_VARIANT -ErrorAction SilentlyContinue
}

Describe "Expand-GetOperation 模式驗證 (Lite)" -Tag "Unit", "Lite" {
    # 這些測試不需要 SSH 連線，只測試危險字元驗證邏輯
    
    It "應該允許標準萬用字元 *" {
        $pattern = "*.log"
        $pattern -match '[;|$`<>&''"\r\n]' | Should -Be $false
    }

    It "應該允許標準萬用字元 ?" {
        $pattern = "file?.txt"
        $pattern -match '[;|$`<>&''"\r\n]' | Should -Be $false
    }

    It "應該允許字元類 []" {
        $pattern = "file[0-9].txt"
        $pattern -match '[;|$`<>&''"\r\n]' | Should -Be $false
    }

    It "應該拒絕分號 ;" {
        $pattern = "*.log;rm -rf /"
        $pattern -match '[;|$`<>&''"\r\n]' | Should -Be $true
    }

    It "應該拒絕管道 |" {
        $pattern = "*.log|cat /etc/passwd"
        $pattern -match '[;|$`<>&''"\r\n]' | Should -Be $true
    }

    It "應該拒絕變數展開 $" {
        $pattern = '*.log$HOME'
        $pattern -match '[;|$`<>&''"\r\n]' | Should -Be $true
    }

    It "應該拒絕反引號" {
        $backtick = [char]0x60
        $pattern = "*.log${backtick}id${backtick}"
        $pattern -match '[;|$`<>&''"\r\n]' | Should -Be $true
    }

    It "應該拒絕 & 符號" {
        $pattern = "*.log&"
        $pattern -match '[;|$`<>&''"\r\n]' | Should -Be $true
    }

    It "應該拒絕單引號" {
        $pattern = "file'*.log"
        $pattern -match '[;|$`<>&''"\r\n]' | Should -Be $true
    }

    It "應該拒絕雙引號" {
        $pattern = 'file"*.log'
        $pattern -match '[;|$`<>&''"\r\n]' | Should -Be $true
    }

    It "應該拒絕換行符" {
        $pattern = "*.log`nrm -rf /"
        $pattern -match '[;|$`<>&''"\r\n]' | Should -Be $true
    }

    It "應該拒絕回車符" {
        $pattern = "*.log`rrm -rf /"
        $pattern -match '[;|$`<>&''"\r\n]' | Should -Be $true
    }
}

Describe "Expand-GetOperation (Lite)" -Tag "Integration", "Lite" {
    BeforeAll {
        $script:ServerRunning = $false
        $container = docker ps --filter "name=vsftp-test-server" --format "{{.Names}}" 2>$null
        $script:ServerRunning = ($container -eq "vsftp-test-server")
        
        $script:SshHost = "testuser@localhost"
        $script:Port = 2222
        $script:KeyFile = "$PSScriptRoot/../../secrets/id_ed25519"
    }

    It "應該展開遠端萬用字元" {
        if (-not $script:ServerRunning) {
            Set-ItResult -Skipped -Because "測試伺服器未運行"
            return
        }

        InModuleScope vSFTP -Parameters @{ SshHost = $script:SshHost; Port = $script:Port; KeyFile = $script:KeyFile } {
            $ops = @([PSCustomObject]@{
                Action      = 'get'
                LocalPath   = '/tmp/*.log'
                RemotePath  = '/home/testuser/upload/*.log'
                Line        = 1
                HasWildcard = $true
            })

            $result = Expand-GetOperation -Operations $ops -SshHost $SshHost -Port $Port -KeyFile $KeyFile -RemoteOS Linux

            $result.Count | Should -BeGreaterOrEqual 1
            $result | ForEach-Object { $_.HasWildcard | Should -Be $false }
        }
    }

    It "應該拒絕含危險字元的模式（分號）" {
        if (-not $script:ServerRunning) {
            Set-ItResult -Skipped -Because "測試伺服器未運行"
            return
        }

        InModuleScope vSFTP -Parameters @{ SshHost = $script:SshHost; Port = $script:Port; KeyFile = $script:KeyFile } {
            $ops = @([PSCustomObject]@{
                Action      = 'get'
                LocalPath   = '/tmp/test'
                RemotePath  = '/home/testuser/upload/;rm -rf /'
                Line        = 1
                HasWildcard = $true
            })

            { Expand-GetOperation -Operations $ops -SshHost $SshHost -Port $Port -KeyFile $KeyFile -RemoteOS Linux } | Should -Throw "*dangerous*"
        }
    }

    It "應該保留非萬用字元操作" {
        if (-not $script:ServerRunning) {
            Set-ItResult -Skipped -Because "測試伺服器未運行"
            return
        }

        InModuleScope vSFTP -Parameters @{ SshHost = $script:SshHost; Port = $script:Port; KeyFile = $script:KeyFile } {
            $ops = @(
                [PSCustomObject]@{
                    Action      = 'get'
                    LocalPath   = '/tmp/test.txt'
                    RemotePath  = '/home/testuser/upload/remote-file.txt'
                    Line        = 1
                    HasWildcard = $false
                }
            )

            $result = Expand-GetOperation -Operations $ops -SshHost $SshHost -Port $Port -KeyFile $KeyFile -RemoteOS Linux

            $result.Count | Should -Be 1
            $result[0].RemotePath | Should -Be '/home/testuser/upload/remote-file.txt'
        }
    }
}
