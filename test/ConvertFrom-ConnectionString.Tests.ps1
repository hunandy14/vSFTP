BeforeAll {
    Import-Module "$PSScriptRoot/../src/vSFTP.psd1" -Force
}

Describe "ConvertFrom-ConnectionString" -Tag "Unit" {
    It "應該解析完整連線字串" {
        $result = InModuleScope vSFTP {
            ConvertFrom-ConnectionString "HostName=example.com;Port=2222;User=admin;IdentityFile=/path/to/key"
        }
        
        $result.Host | Should -Be "example.com"
        $result.Port | Should -Be 2222
        $result.User | Should -Be "admin"
        $result.KeyFile | Should -Be "/path/to/key"
    }

    It "應該在省略 Port 時使用預設值 22" {
        $result = InModuleScope vSFTP {
            ConvertFrom-ConnectionString "HostName=example.com;User=admin;IdentityFile=/path/to/key"
        }
        
        $result.Port | Should -Be 22
    }

    It "應該支援任意欄位順序" {
        $result = InModuleScope vSFTP {
            ConvertFrom-ConnectionString "User=admin;IdentityFile=/path/to/key;HostName=example.com;Port=22"
        }
        
        $result.Host | Should -Be "example.com"
        $result.User | Should -Be "admin"
        $result.KeyFile | Should -Be "/path/to/key"
    }

    It "應該處理欄位周圍的空白" {
        $result = InModuleScope vSFTP {
            ConvertFrom-ConnectionString "HostName = example.com ; User = admin ; IdentityFile = /path/to/key"
        }
        
        $result.Host | Should -Be "example.com"
        $result.User | Should -Be "admin"
        $result.KeyFile | Should -Be "/path/to/key"
    }

    It "應該正確處理 Windows 路徑" {
        $result = InModuleScope vSFTP {
            ConvertFrom-ConnectionString "HostName=example.com;User=admin;IdentityFile=C:\Users\me\.ssh\id_rsa"
        }
        
        $result.KeyFile | Should -Be "C:\Users\me\.ssh\id_rsa"
    }

    It "應該在缺少 HostName 時拋出錯誤" {
        { 
            InModuleScope vSFTP { 
                ConvertFrom-ConnectionString "User=admin;IdentityFile=/path/to/key" 
            } 
        } | Should -Throw "*Missing required fields*HostName*"
    }

    It "應該在缺少 User 時拋出錯誤" {
        { 
            InModuleScope vSFTP { 
                ConvertFrom-ConnectionString "HostName=example.com;IdentityFile=/path/to/key" 
            } 
        } | Should -Throw "*Missing required fields*User*"
    }

    It "應該在缺少多個欄位時列出所有缺少的欄位" {
        { 
            InModuleScope vSFTP { 
                ConvertFrom-ConnectionString "HostName=example.com" 
            } 
        } | Should -Throw "*Missing required fields*User*"
    }

    It "應該支援 Pipeline 輸入" {
        $result = InModuleScope vSFTP {
            "HostName=example.com;User=admin;IdentityFile=/path/to/key" | ConvertFrom-ConnectionString
        }
        
        $result.Host | Should -Be "example.com"
    }

    It "應該忽略未知的欄位" {
        $result = InModuleScope vSFTP {
            ConvertFrom-ConnectionString "HostName=example.com;User=admin;IdentityFile=/path/to/key;unknown=value"
        }
        
        $result.Host | Should -Be "example.com"
        $result.PSObject.Properties.Name | Should -Not -Contain "unknown"
    }

    It "應該處理大小寫不敏感的欄位名稱" {
        $result = InModuleScope vSFTP {
            ConvertFrom-ConnectionString "HOSTNAME=example.com;USER=admin;IDENTITYFILE=/path/to/key;PORT=22"
        }
        
        $result.Host | Should -Be "example.com"
        $result.User | Should -Be "admin"
        $result.KeyFile | Should -Be "/path/to/key"
        $result.Port | Should -Be 22
    }

    It "應該在空字串時拋出錯誤" {
        { 
            InModuleScope vSFTP { 
                ConvertFrom-ConnectionString "" 
            } 
        } | Should -Throw  # PowerShell 拒絕空字串作為 Mandatory 參數
    }

    It "應該在只有分號時拋出錯誤" {
        { 
            InModuleScope vSFTP { 
                ConvertFrom-ConnectionString ";;;" 
            } 
        } | Should -Throw "*Missing required fields*"
    }

    It "應該在重複欄位時使用後者的值" {
        $result = InModuleScope vSFTP {
            ConvertFrom-ConnectionString "HostName=first.com;User=admin;IdentityFile=/path/to/key;HostName=second.com"
        }
        
        $result.Host | Should -Be "second.com"
    }

    It "應該在 Port 非數字時拋出錯誤" {
        { 
            InModuleScope vSFTP { 
                ConvertFrom-ConnectionString "HostName=example.com;User=admin;IdentityFile=/path/to/key;Port=abc" 
            } 
        } | Should -Throw
    }

    It "應該支援 User 包含 @ 符號" {
        $result = InModuleScope vSFTP {
            ConvertFrom-ConnectionString "HostName=example.com;User=test@domain.com;IdentityFile=/path/to/key"
        }
        
        $result.User | Should -Be "test@domain.com"
    }

    It "應該支援 IdentityFile 包含空格的路徑" {
        $result = InModuleScope vSFTP {
            ConvertFrom-ConnectionString "HostName=example.com;User=admin;IdentityFile=/path/to/my key"
        }
        
        $result.KeyFile | Should -Be "/path/to/my key"
    }

    It "應該支援值包含等號" {
        $result = InModuleScope vSFTP {
            ConvertFrom-ConnectionString "HostName=example.com;User=admin;IdentityFile=/path/to/key=test"
        }
        
        $result.KeyFile | Should -Be "/path/to/key=test"
    }

    Context "省略 IdentityFile 時自動搜尋" {
        It "應該自動找到預設金鑰" {
            $result = InModuleScope vSFTP {
                Mock Get-DefaultSshKey { return '/home/user/.ssh/id_rsa' }
                ConvertFrom-ConnectionString "HostName=example.com;User=admin"
            }
            
            $result.KeyFile | Should -Be '/home/user/.ssh/id_rsa'
        }

        It "應該在找不到任何金鑰時拋出錯誤" {
            { 
                InModuleScope vSFTP { 
                    Mock Get-DefaultSshKey { return $null }
                    ConvertFrom-ConnectionString "HostName=example.com;User=admin" 
                } 
            } | Should -Throw "*No IdentityFile specified and no default key found*"
        }

        It "指定 IdentityFile 時不應自動搜尋" {
            $result = InModuleScope vSFTP {
                Mock Get-DefaultSshKey { throw "Should not be called" }
                ConvertFrom-ConnectionString "HostName=example.com;User=admin;IdentityFile=/explicit/path"
            }
            
            $result.KeyFile | Should -Be "/explicit/path"
        }
    }
}
