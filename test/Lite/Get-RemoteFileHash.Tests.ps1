BeforeAll {
    $env:VSFTP_VARIANT = 'Lite'
    Import-Module "$PSScriptRoot/../../src/vSFTP.psd1" -Force
}

AfterAll {
    Remove-Item Env:VSFTP_VARIANT -ErrorAction SilentlyContinue
}

Describe "Get-RemoteFileHash (Lite)" -Tag "Integration", "Lite" {
    BeforeAll {
        $script:ServerRunning = $false
        $container = docker ps --filter "name=vsftp-test-server" --format "{{.Names}}" 2>$null
        $script:ServerRunning = ($container -eq "vsftp-test-server")
        
        $script:SshHost = "testuser@localhost"
        $script:Port = 2222
        $script:KeyFile = "$PSScriptRoot/../../secrets/id_ed25519"
    }

    It "應該取得 Linux 檔案的 SHA256 雜湊和絕對路徑" {
        if (-not $script:ServerRunning) {
            Set-ItResult -Skipped -Because "測試伺服器未運行"
            return
        }

        InModuleScope vSFTP -Parameters @{ SshHost = $script:SshHost; Port = $script:Port; KeyFile = $script:KeyFile } {
            $result = Get-RemoteFileHash -SshHost $SshHost -Port $Port -KeyFile $KeyFile -RemotePath "/home/testuser/upload/remote-file.txt" -RemoteOS "Linux"
            $result.Hash | Should -Match "^[A-F0-9]{64}$"
            $result.AbsolutePath | Should -Be "/home/testuser/upload/remote-file.txt"
        }
    }

    It "應該正確處理 Base64 編碼路徑" {
        if (-not $script:ServerRunning) {
            Set-ItResult -Skipped -Because "測試伺服器未運行"
            return
        }

        InModuleScope vSFTP -Parameters @{ SshHost = $script:SshHost; Port = $script:Port; KeyFile = $script:KeyFile } {
            $result = Get-RemoteFileHash -SshHost $SshHost -Port $Port -KeyFile $KeyFile -RemotePath "/home/testuser/upload/access.log" -RemoteOS "Linux"
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

        InModuleScope vSFTP -Parameters @{ SshHost = $script:SshHost; Port = $script:Port; KeyFile = $script:KeyFile } {
            { Get-RemoteFileHash -SshHost $SshHost -Port $Port -KeyFile $KeyFile -RemotePath "/nonexistent/file.txt" -RemoteOS "Linux" } | Should -Throw
        }
    }
}
