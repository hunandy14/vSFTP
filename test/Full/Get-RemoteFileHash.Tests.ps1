BeforeAll {
    Import-Module "$PSScriptRoot/../../src/vSFTP.psd1" -Force
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

    It "應該取得 Linux 檔案的 SHA256 雜湊和絕對路徑" {
        if (-not $script:ServerRunning) {
            Set-ItResult -Skipped -Because "測試伺服器未運行"
            return
        }

        InModuleScope vSFTP -Parameters @{ SessionId = $script:Session.SessionId } {
            $result = Get-RemoteFileHash -SessionId $SessionId -RemotePath "/home/testuser/upload/remote-file.txt" -RemoteOS "Linux"
            $result.Hash | Should -Match "^[A-F0-9]{64}$"
            $result.AbsolutePath | Should -Be "/home/testuser/upload/remote-file.txt"
        }
    }

    It "應該正確處理 Base64 編碼路徑" {
        if (-not $script:ServerRunning) {
            Set-ItResult -Skipped -Because "測試伺服器未運行"
            return
        }

        InModuleScope vSFTP -Parameters @{ SessionId = $script:Session.SessionId } {
            $result = Get-RemoteFileHash -SessionId $SessionId -RemotePath "/home/testuser/upload/access.log" -RemoteOS "Linux"
            $result.Hash | Should -Match "^[A-F0-9]{64}$"
            $result.Hash.Length | Should -Be 64
            $result.AbsolutePath | Should -BeLike "/home/testuser/upload/access.log"
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
