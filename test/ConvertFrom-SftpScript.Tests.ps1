BeforeAll {
    # 匯入模組
    $ModulePath = Join-Path $PSScriptRoot "../src/vSFTP.psd1"
    Import-Module $ModulePath -Force
}

Describe "ConvertFrom-SftpScript" {
    BeforeAll {
        $TestScriptsDir = Join-Path $PSScriptRoot "scripts"
        $TempDir = Join-Path $PSScriptRoot "temp"
        if (-not (Test-Path $TempDir)) {
            New-Item -ItemType Directory -Path $TempDir | Out-Null
        }
    }

    AfterAll {
        if (Test-Path $TempDir) {
            Remove-Item $TempDir -Recurse -Force
        }
    }

    Context "解析 PUT 指令" {
        It "應該解析單一 put 指令" {
            InModuleScope vSFTP -Parameters @{ TempDir = $TempDir } {
                $script = @"
lcd $TempDir
cd /remote
put test.txt
"@
                $scriptFile = Join-Path $TempDir "test-put.sftp"
                $script | Set-Content $scriptFile
                "test content" | Set-Content (Join-Path $TempDir "test.txt")

                $result = ConvertFrom-SftpScript -ScriptFile $scriptFile

                $result | Should -HaveCount 1
                $result[0].Action | Should -Be "put"
                $result[0].RemotePath | Should -Be "/remote/test.txt"
            }
        }

        It "應該展開本地萬用字元" {
            InModuleScope vSFTP -Parameters @{ TempDir = $TempDir } {
                $script = @"
lcd $TempDir
cd /remote
put *.txt
"@
                $scriptFile = Join-Path $TempDir "test-wildcard.sftp"
                $script | Set-Content $scriptFile
                "file1" | Set-Content (Join-Path $TempDir "a1.txt")
                "file2" | Set-Content (Join-Path $TempDir "a2.txt")

                $result = ConvertFrom-SftpScript -ScriptFile $scriptFile

                $result.Count | Should -BeGreaterOrEqual 2
            }
        }
    }

    Context "解析 GET 指令" {
        It "應該解析單一 get 指令" {
            InModuleScope vSFTP -Parameters @{ TempDir = $TempDir } {
                $script = @"
lcd $TempDir
cd /remote
get data.txt
"@
                $scriptFile = Join-Path $TempDir "test-get.sftp"
                $script | Set-Content $scriptFile

                $result = ConvertFrom-SftpScript -ScriptFile $scriptFile

                $result | Should -HaveCount 1
                $result[0].Action | Should -Be "get"
                $result[0].RemotePath | Should -Be "/remote/data.txt"
            }
        }

        It "應該標記萬用字元" {
            InModuleScope vSFTP -Parameters @{ TempDir = $TempDir } {
                $script = @"
cd /logs
get *.log
"@
                $scriptFile = Join-Path $TempDir "test-wildcard-get.sftp"
                $script | Set-Content $scriptFile

                $result = ConvertFrom-SftpScript -ScriptFile $scriptFile

                $result[0].HasWildcard | Should -Be $true
            }
        }
    }

    Context "解析 CD/LCD 指令" {
        It "應該追蹤 cd 路徑" {
            InModuleScope vSFTP -Parameters @{ TempDir = $TempDir } {
                $script = @"
lcd $TempDir
cd /home
cd user
cd uploads
put test.txt
"@
                $scriptFile = Join-Path $TempDir "test-cd.sftp"
                $script | Set-Content $scriptFile
                "test" | Set-Content (Join-Path $TempDir "test.txt")

                $result = ConvertFrom-SftpScript -ScriptFile $scriptFile

                $result[0].RemotePath | Should -Be "/home/user/uploads/test.txt"
            }
        }

        It "應該處理 cd .." {
            InModuleScope vSFTP -Parameters @{ TempDir = $TempDir } {
                $script = @"
lcd $TempDir
cd /home/user/deep
cd ..
put test.txt
"@
                $scriptFile = Join-Path $TempDir "test-cd-parent.sftp"
                $script | Set-Content $scriptFile
                "test" | Set-Content (Join-Path $TempDir "test.txt")

                $result = ConvertFrom-SftpScript -ScriptFile $scriptFile

                $result[0].RemotePath | Should -Be "/home/user/test.txt"
            }
        }
    }

    Context "錯誤處理" {
        It "應該在檔案不存在時拋出錯誤" {
            InModuleScope vSFTP {
                { ConvertFrom-SftpScript -ScriptFile "/nonexistent/file.sftp" } | Should -Throw
            }
        }

        It "應該跳過註解和空行" {
            InModuleScope vSFTP -Parameters @{ TempDir = $TempDir } {
                $script = @"
# 這是註解
lcd $TempDir

cd /remote
# 另一個註解
put test.txt
"@
                $scriptFile = Join-Path $TempDir "test-comments.sftp"
                $script | Set-Content $scriptFile
                "test" | Set-Content (Join-Path $TempDir "test.txt")

                $result = ConvertFrom-SftpScript -ScriptFile $scriptFile

                $result | Should -HaveCount 1
            }
        }
    }
}
