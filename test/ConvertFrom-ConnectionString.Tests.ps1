BeforeAll {
    Import-Module "$PSScriptRoot/../src/vSFTP.psd1" -Force
}

Describe "ConvertFrom-ConnectionString" -Tag "Unit" {
    It "應該解析完整連線字串" {
        $result = InModuleScope vSFTP {
            ConvertFrom-ConnectionString "host=example.com;port=2222;user=admin;key=/path/to/key"
        }
        
        $result.Host | Should -Be "example.com"
        $result.Port | Should -Be 2222
        $result.User | Should -Be "admin"
        $result.KeyFile | Should -Be "/path/to/key"
    }

    It "應該在省略 port 時使用預設值 22" {
        $result = InModuleScope vSFTP {
            ConvertFrom-ConnectionString "host=example.com;user=admin;key=/path/to/key"
        }
        
        $result.Port | Should -Be 22
    }

    It "應該支援任意欄位順序" {
        $result = InModuleScope vSFTP {
            ConvertFrom-ConnectionString "user=admin;key=/path/to/key;host=example.com;port=22"
        }
        
        $result.Host | Should -Be "example.com"
        $result.User | Should -Be "admin"
        $result.KeyFile | Should -Be "/path/to/key"
    }

    It "應該處理欄位周圍的空白" {
        $result = InModuleScope vSFTP {
            ConvertFrom-ConnectionString "host = example.com ; user = admin ; key = /path/to/key"
        }
        
        $result.Host | Should -Be "example.com"
        $result.User | Should -Be "admin"
        $result.KeyFile | Should -Be "/path/to/key"
    }

    It "應該正確處理 Windows 路徑" {
        $result = InModuleScope vSFTP {
            ConvertFrom-ConnectionString "host=example.com;user=admin;key=C:\Users\me\.ssh\id_rsa"
        }
        
        $result.KeyFile | Should -Be "C:\Users\me\.ssh\id_rsa"
    }

    It "應該在缺少 host 時拋出錯誤" {
        { 
            InModuleScope vSFTP { 
                ConvertFrom-ConnectionString "user=admin;key=/path/to/key" 
            } 
        } | Should -Throw "*Missing required fields*host*"
    }

    It "應該在缺少 user 時拋出錯誤" {
        { 
            InModuleScope vSFTP { 
                ConvertFrom-ConnectionString "host=example.com;key=/path/to/key" 
            } 
        } | Should -Throw "*Missing required fields*user*"
    }

    It "應該在缺少 key 時拋出錯誤" {
        { 
            InModuleScope vSFTP { 
                ConvertFrom-ConnectionString "host=example.com;user=admin" 
            } 
        } | Should -Throw "*Missing required fields*key*"
    }

    It "應該在缺少多個欄位時列出所有缺少的欄位" {
        { 
            InModuleScope vSFTP { 
                ConvertFrom-ConnectionString "host=example.com" 
            } 
        } | Should -Throw "*Missing required fields*user*key*"
    }

    It "應該支援 Pipeline 輸入" {
        $result = InModuleScope vSFTP {
            "host=example.com;user=admin;key=/path/to/key" | ConvertFrom-ConnectionString
        }
        
        $result.Host | Should -Be "example.com"
    }

    It "應該忽略未知的欄位" {
        $result = InModuleScope vSFTP {
            ConvertFrom-ConnectionString "host=example.com;user=admin;key=/path/to/key;unknown=value"
        }
        
        $result.Host | Should -Be "example.com"
        $result.PSObject.Properties.Name | Should -Not -Contain "unknown"
    }

    It "應該處理大小寫不敏感的欄位名稱" {
        $result = InModuleScope vSFTP {
            ConvertFrom-ConnectionString "HOST=example.com;USER=admin;KEY=/path/to/key;PORT=22"
        }
        
        $result.Host | Should -Be "example.com"
        $result.User | Should -Be "admin"
        $result.KeyFile | Should -Be "/path/to/key"
        $result.Port | Should -Be 22
    }
}
