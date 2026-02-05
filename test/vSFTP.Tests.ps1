BeforeAll {
    Import-Module "$PSScriptRoot/../src/vSFTP.psd1" -Force
}

Describe "vSFTP 模組" -Tag "Unit" {
    Context "模組載入" {
        It "應該成功匯入模組" {
            Get-Module vSFTP | Should -Not -BeNullOrEmpty
        }

        It "應該匯出 Invoke-vSFTP 函數" {
            Get-Command Invoke-vSFTP -Module vSFTP | Should -Not -BeNullOrEmpty
        }

        It "應該包含所有必要的私有函數" {
            InModuleScope vSFTP {
                Get-Command ConvertFrom-SftpScript | Should -Not -BeNullOrEmpty
                Get-Command ConvertFrom-ConnectionString | Should -Not -BeNullOrEmpty
                Get-Command Get-RemoteFileHash | Should -Not -BeNullOrEmpty
                Get-Command Test-FileHash | Should -Not -BeNullOrEmpty
                Get-Command Expand-GetOperation | Should -Not -BeNullOrEmpty
                Get-Command Invoke-SftpExe | Should -Not -BeNullOrEmpty
            }
        }
    }
}
