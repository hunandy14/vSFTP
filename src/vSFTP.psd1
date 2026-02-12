@{
    RootModule = 'vSFTP.psm1'
    ModuleVersion = '1.1.1'
    GUID = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
    Author = 'kaede'
    Description = 'SFTP with SHA256 hash verification'
    PowerShellVersion = '7.0'
    # RequiredModules 由 .psm1 根據 VSFTP_VARIANT 決定
    FunctionsToExport = @('Invoke-vSFTP')
    PrivateData = @{
        PSData = @{
            Tags = @('SFTP', 'SSH', 'Hash', 'Verification', 'Transfer')
            ProjectUri = 'https://github.com/hunandy14/vsftp'
        }
    }
}
