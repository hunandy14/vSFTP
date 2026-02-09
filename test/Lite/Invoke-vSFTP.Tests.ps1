BeforeAll {
    $env:VSFTP_VARIANT = 'Lite'
    Import-Module "$PSScriptRoot/../../src/vSFTP.psd1" -Force
}

AfterAll {
    Remove-Item Env:VSFTP_VARIANT -ErrorAction SilentlyContinue
}

Describe "Invoke-vSFTP 連線字串 (Lite)" -Tag "Unit", "Lite" {
    It "應該在缺少 SFTP_CONNECTION 時顯示錯誤" {
        $original = $env:SFTP_CONNECTION
        
        try {
            $env:SFTP_CONNECTION = $null
            
            $output = & { try { Invoke-vSFTP -ScriptFile "test/scripts/test-upload.sftp" } catch {} } 6>&1 2>&1 | Out-String
            $output | Should -Match "SFTP_CONNECTION not set"
        } finally {
            $env:SFTP_CONNECTION = $original
        }
    }

    It "應該在缺少必要欄位時顯示錯誤" {
        $original = $env:SFTP_CONNECTION
        
        try {
            $env:SFTP_CONNECTION = "HostName=localhost"
            
            $output = & { try { Invoke-vSFTP -ScriptFile "test/scripts/test-upload.sftp" } catch {} } 6>&1 2>&1 | Out-String
            $output | Should -Match "Missing required fields"
        } finally {
            $env:SFTP_CONNECTION = $original
        }
    }

    It "應該正確解析完整連線字串（含 Port）" {
        $original = $env:SFTP_CONNECTION
        
        try {
            $env:SFTP_CONNECTION = "HostName=nonexistent.host;Port=2222;User=testuser;IdentityFile=secrets/id_ed25519"
            
            $output = & { try { Invoke-vSFTP -ScriptFile "test/scripts/test-upload.sftp" } catch {} } 6>&1 2>&1 | Out-String
            $output | Should -Match "testuser@nonexistent.host:2222"
        } finally {
            $env:SFTP_CONNECTION = $original
        }
    }

    It "應該支援任意欄位順序" {
        $original = $env:SFTP_CONNECTION
        
        try {
            $env:SFTP_CONNECTION = "User=testuser;IdentityFile=secrets/id_ed25519;HostName=order.test;Port=22"
            
            $output = & { try { Invoke-vSFTP -ScriptFile "test/scripts/test-upload.sftp" } catch {} } 6>&1 2>&1 | Out-String
            $output | Should -Match "testuser@order.test:22"
        } finally {
            $env:SFTP_CONNECTION = $original
        }
    }

    It "應該在省略 Port 時使用預設值 22" {
        $original = $env:SFTP_CONNECTION
        
        try {
            $env:SFTP_CONNECTION = "HostName=default-port.test;User=testuser;IdentityFile=secrets/id_ed25519"
            
            $output = & { try { Invoke-vSFTP -ScriptFile "test/scripts/test-upload.sftp" } catch {} } 6>&1 2>&1 | Out-String
            $output | Should -Match "testuser@default-port.test:22"
        } finally {
            $env:SFTP_CONNECTION = $original
        }
    }

    It "應該正確處理 Windows 路徑" {
        $original = $env:SFTP_CONNECTION
        
        try {
            $env:SFTP_CONNECTION = "HostName=win.test;User=testuser;IdentityFile=C:\Users\me\.ssh\id_rsa"
            
            # DryRun 不會 throw（成功返回）
            $output = & { Invoke-vSFTP -ScriptFile "test/scripts/test-upload.sftp" -DryRun } 6>&1 2>&1 | Out-String
            $output | Should -Match "C:\\Users\\me\\\.ssh\\id_rsa"
        } finally {
            $env:SFTP_CONNECTION = $original
        }
    }

    It "應該處理欄位周圍的空白" {
        $original = $env:SFTP_CONNECTION
        
        try {
            $env:SFTP_CONNECTION = "HostName = space.test ; User = testuser ; IdentityFile = secrets/id_ed25519"
            
            $output = & { try { Invoke-vSFTP -ScriptFile "test/scripts/test-upload.sftp" } catch {} } 6>&1 2>&1 | Out-String
            $output | Should -Match "testuser@space.test:22"
        } finally {
            $env:SFTP_CONNECTION = $original
        }
    }
}

Describe "Invoke-vSFTP 整合測試 (Lite)" -Tag "Integration", "Lite" {
    BeforeAll {
        $script:ServerRunning = $false
        $container = docker ps --filter "name=vsftp-test-server" --format "{{.Names}}" 2>$null
        $script:ServerRunning = ($container -eq "vsftp-test-server")
        
        if ($script:ServerRunning) {
            $env:SFTP_CONNECTION = "HostName=localhost;Port=2222;User=testuser;IdentityFile=secrets/id_ed25519"
        }
    }

    It "應該成功執行 PUT 操作" {
        if (-not $script:ServerRunning) {
            Set-ItResult -Skipped -Because "測試伺服器未運行"
            return
        }

        $output = & { Invoke-vSFTP -ScriptFile "test/scripts/test-upload.sftp" } 6>&1 2>&1 | Out-String
        $output | Should -Match "1 passed, 0 failed"
    }

    It "應該成功執行 GET 操作" {
        if (-not $script:ServerRunning) {
            Set-ItResult -Skipped -Because "測試伺服器未運行"
            return
        }

        $output = & { Invoke-vSFTP -ScriptFile "test/scripts/test-download.sftp" } 6>&1 2>&1 | Out-String
        $output | Should -Match "1 passed, 0 failed"
    }

    It "應該成功展開萬用字元並執行 GET" {
        if (-not $script:ServerRunning) {
            Set-ItResult -Skipped -Because "測試伺服器未運行"
            return
        }

        $output = & { Invoke-vSFTP -ScriptFile "test/scripts/test-wildcard.sftp" } 6>&1 2>&1 | Out-String
        $output | Should -Match "3 passed, 0 failed"
    }

    It "DryRun 模式應該只解析不執行" {
        if (-not $script:ServerRunning) {
            Set-ItResult -Skipped -Because "測試伺服器未運行"
            return
        }

        $output = & { Invoke-vSFTP -ScriptFile "test/scripts/test-upload.sftp" -DryRun } 6>&1 2>&1 | Out-String
        $output | Should -Match "Dry Run"
        $output | Should -Not -Match "Transferring"
    }
}
