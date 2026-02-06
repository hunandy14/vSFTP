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

    It "應該在缺少多個欄位時列出所有缺少的欄位" {
        { 
            InModuleScope vSFTP { 
                ConvertFrom-ConnectionString "host=example.com" 
            } 
        } | Should -Throw "*Missing required fields*user*"
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
            ConvertFrom-ConnectionString "host=first.com;user=admin;key=/path/to/key;host=second.com"
        }
        
        $result.Host | Should -Be "second.com"
    }

    It "應該在 port 非數字時拋出錯誤" {
        { 
            InModuleScope vSFTP { 
                ConvertFrom-ConnectionString "host=example.com;user=admin;key=/path/to/key;port=abc" 
            } 
        } | Should -Throw
    }

    It "應該支援 user 包含 @ 符號" {
        $result = InModuleScope vSFTP {
            ConvertFrom-ConnectionString "host=example.com;user=test@domain.com;key=/path/to/key"
        }
        
        $result.User | Should -Be "test@domain.com"
    }

    It "應該支援 key 包含空格的路徑" {
        $result = InModuleScope vSFTP {
            ConvertFrom-ConnectionString "host=example.com;user=admin;key=/path/to/my key"
        }
        
        $result.KeyFile | Should -Be "/path/to/my key"
    }

    It "應該支援值包含等號" {
        $result = InModuleScope vSFTP {
            ConvertFrom-ConnectionString "host=example.com;user=admin;key=/path/to/key=test"
        }
        
        $result.KeyFile | Should -Be "/path/to/key=test"
    }

    Context "省略 key 時自動搜尋" {
        It "應該自動找到預設金鑰" {
            $result = InModuleScope vSFTP {
                Mock Get-DefaultSshKey { return '/home/user/.ssh/id_rsa' }
                ConvertFrom-ConnectionString "host=example.com;user=admin"
            }
            
            $result.KeyFile | Should -Be '/home/user/.ssh/id_rsa'
        }

        It "應該在找不到任何金鑰時拋出錯誤" {
            { 
                InModuleScope vSFTP { 
                    Mock Get-DefaultSshKey { return $null }
                    ConvertFrom-ConnectionString "host=example.com;user=admin" 
                } 
            } | Should -Throw "*No SSH key specified and no default key found*"
        }

        It "指定 key 時不應自動搜尋" {
            $result = InModuleScope vSFTP {
                Mock Get-DefaultSshKey { throw "Should not be called" }
                ConvertFrom-ConnectionString "host=example.com;user=admin;key=/explicit/path"
            }
            
            $result.KeyFile | Should -Be "/explicit/path"
        }
    }
}
