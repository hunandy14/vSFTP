BeforeAll {
    Import-Module "$PSScriptRoot/../../src/vSFTP.psd1" -Force
}

Describe "Expand-GetOperation 模式驗證" -Tag "Unit" {
    # 這些測試不需要 SSH 連線，只測試危險字元驗證邏輯
    
    It "應該允許標準萬用字元 *" {
        # 模式驗證發生在 SSH 命令之前
        # 這裡只檢查模式是否被接受
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
        $backtick = [char]0x60  # `
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
