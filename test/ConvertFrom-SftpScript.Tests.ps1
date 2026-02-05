BeforeAll {
    # 匯入模組
    $ModulePath = Join-Path $PSScriptRoot "../src/vSFTP.psd1"
    Import-Module $ModulePath -Force
}

Describe "ConvertFrom-SftpScript" {
    BeforeAll {
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

        It "應該支援指定遠端路徑" {
            InModuleScope vSFTP -Parameters @{ TempDir = $TempDir } {
                $script = @"
lcd $TempDir
put test.txt /upload/renamed.txt
"@
                $scriptFile = Join-Path $TempDir "test-put-dest.sftp"
                $script | Set-Content $scriptFile
                "test" | Set-Content (Join-Path $TempDir "test.txt")

                $result = ConvertFrom-SftpScript -ScriptFile $scriptFile

                $result[0].RemotePath | Should -Be "/upload/renamed.txt"
            }
        }

        It "應該支援遠端目錄路徑（結尾有斜線）" {
            InModuleScope vSFTP -Parameters @{ TempDir = $TempDir } {
                $script = @"
lcd $TempDir
put test.txt /upload/
"@
                $scriptFile = Join-Path $TempDir "test-put-dir.sftp"
                $script | Set-Content $scriptFile
                "test" | Set-Content (Join-Path $TempDir "test.txt")

                $result = ConvertFrom-SftpScript -ScriptFile $scriptFile

                $result[0].RemotePath | Should -Be "/upload/test.txt"
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

        It "應該支援指定本地路徑" {
            InModuleScope vSFTP -Parameters @{ TempDir = $TempDir } {
                $script = @"
lcd $TempDir
get /remote/data.txt local-copy.txt
"@
                $scriptFile = Join-Path $TempDir "test-get-dest.sftp"
                $script | Set-Content $scriptFile

                $result = ConvertFrom-SftpScript -ScriptFile $scriptFile

                $result[0].LocalPath | Should -BeLike "*local-copy.txt"
            }
        }
    }

    Context "解析 CD 指令" {
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

        It "應該處理多次 cd .." {
            InModuleScope vSFTP -Parameters @{ TempDir = $TempDir } {
                $script = @"
lcd $TempDir
cd /a/b/c/d
cd ..
cd ..
put test.txt
"@
                $scriptFile = Join-Path $TempDir "test-cd-multi-parent.sftp"
                $script | Set-Content $scriptFile
                "test" | Set-Content (Join-Path $TempDir "test.txt")

                $result = ConvertFrom-SftpScript -ScriptFile $scriptFile

                $result[0].RemotePath | Should -Be "/a/b/test.txt"
            }
        }

        It "應該處理絕對路徑 cd" {
            InModuleScope vSFTP -Parameters @{ TempDir = $TempDir } {
                $script = @"
lcd $TempDir
cd /first/path
cd /second/path
put test.txt
"@
                $scriptFile = Join-Path $TempDir "test-cd-abs.sftp"
                $script | Set-Content $scriptFile
                "test" | Set-Content (Join-Path $TempDir "test.txt")

                $result = ConvertFrom-SftpScript -ScriptFile $scriptFile

                $result[0].RemotePath | Should -Be "/second/path/test.txt"
            }
        }
    }

    Context "解析 LCD 指令" {
        It "應該追蹤 lcd 路徑" {
            InModuleScope vSFTP -Parameters @{ TempDir = $TempDir } {
                # 建立子目錄
                $subDir = Join-Path $TempDir "subdir"
                New-Item -ItemType Directory -Path $subDir -Force | Out-Null
                "test" | Set-Content (Join-Path $subDir "test.txt")

                $script = @"
lcd $TempDir
lcd subdir
cd /remote
put test.txt
"@
                $scriptFile = Join-Path $TempDir "test-lcd.sftp"
                $script | Set-Content $scriptFile

                $result = ConvertFrom-SftpScript -ScriptFile $scriptFile

                $result[0].LocalPath | Should -BeLike "*subdir*test.txt"
            }
        }

        It "應該處理 lcd .." {
            InModuleScope vSFTP -Parameters @{ TempDir = $TempDir } {
                # 建立子目錄結構
                $subDir = Join-Path $TempDir "a/b"
                New-Item -ItemType Directory -Path $subDir -Force | Out-Null
                "test" | Set-Content (Join-Path $TempDir "a/test.txt")

                $script = @"
lcd $TempDir/a/b
lcd ..
cd /remote
put test.txt
"@
                $scriptFile = Join-Path $TempDir "test-lcd-parent.sftp"
                $script | Set-Content $scriptFile

                $result = ConvertFrom-SftpScript -ScriptFile $scriptFile

                $result[0].LocalPath | Should -BeLike "*a*test.txt"
                $result[0].LocalPath | Should -Not -BeLike "*a*b*"
            }
        }

        It "應該處理絕對路徑 lcd" {
            InModuleScope vSFTP -Parameters @{ TempDir = $TempDir } {
                $script = @"
lcd /tmp
lcd $TempDir
cd /remote
put test.txt
"@
                $scriptFile = Join-Path $TempDir "test-lcd-abs.sftp"
                $script | Set-Content $scriptFile
                "test" | Set-Content (Join-Path $TempDir "test.txt")

                $result = ConvertFrom-SftpScript -ScriptFile $scriptFile

                $result[0].LocalPath | Should -BeLike "$TempDir*test.txt"
            }
        }
    }

    Context "混合 CD/LCD" {
        It "應該獨立追蹤本地和遠端路徑" {
            InModuleScope vSFTP -Parameters @{ TempDir = $TempDir } {
                $subDir = Join-Path $TempDir "local-sub"
                New-Item -ItemType Directory -Path $subDir -Force | Out-Null
                "test" | Set-Content (Join-Path $subDir "test.txt")

                $script = @"
lcd $TempDir
cd /remote
lcd local-sub
cd uploads
put test.txt
"@
                $scriptFile = Join-Path $TempDir "test-mixed.sftp"
                $script | Set-Content $scriptFile

                $result = ConvertFrom-SftpScript -ScriptFile $scriptFile

                $result[0].LocalPath | Should -BeLike "*local-sub*test.txt"
                $result[0].RemotePath | Should -Be "/remote/uploads/test.txt"
            }
        }
    }

    Context "錯誤處理" {
        It "應該在腳本檔案不存在時拋出錯誤" {
            InModuleScope vSFTP {
                { ConvertFrom-SftpScript -ScriptFile "/nonexistent/file.sftp" } | Should -Throw
            }
        }

        It "應該在本地檔案不存在時拋出錯誤" {
            InModuleScope vSFTP -Parameters @{ TempDir = $TempDir } {
                $script = @"
lcd $TempDir
put nonexistent-file.txt
"@
                $scriptFile = Join-Path $TempDir "test-missing.sftp"
                $script | Set-Content $scriptFile

                { ConvertFrom-SftpScript -ScriptFile $scriptFile } | Should -Throw "*not exist*"
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

        It "應該忽略不支援的指令" {
            InModuleScope vSFTP -Parameters @{ TempDir = $TempDir } {
                $script = @"
lcd $TempDir
cd /remote
chmod 755 test.txt
mkdir newdir
put test.txt
rm oldfile.txt
"@
                $scriptFile = Join-Path $TempDir "test-unsupported.sftp"
                $script | Set-Content $scriptFile
                "test" | Set-Content (Join-Path $TempDir "test.txt")

                $result = ConvertFrom-SftpScript -ScriptFile $scriptFile

                $result | Should -HaveCount 1
                $result[0].Action | Should -Be "put"
            }
        }
    }

    Context "特殊字元處理" {
        It "應該處理含空格的檔名" -Tag "TODO" {
            # TODO: 需要修復解析器支援引號內的空格
            Set-ItResult -Skipped -Because "解析器尚未支援引號處理"
        }
    }
}
