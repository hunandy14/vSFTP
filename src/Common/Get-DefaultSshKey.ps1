function Get-DefaultSshKey {
    <#
    .SYNOPSIS
        尋找預設的 SSH 私鑰。
    .DESCRIPTION
        按照 OpenSSH 的順序搜尋 ~/.ssh/ 目錄下的私鑰檔案。
        順序參考 openssh-portable/readconf.c:
        1. id_rsa
        2. id_ecdsa
        3. id_ecdsa_sk
        4. id_ed25519
        5. id_ed25519_sk
    .PARAMETER SshDir
        指定 SSH 目錄路徑（測試用）。預設為 ~/.ssh。
    .OUTPUTS
        找到的第一個私鑰的完整路徑，若無則回傳 $null。
    .EXAMPLE
        $key = Get-DefaultSshKey
        if ($key) { Write-Host "Found: $key" }
    #>
    [CmdletBinding()]
    param(
        [string]$SshDir
    )

    # OpenSSH 預設順序（參考 openssh-portable/readconf.c）
    $defaultKeys = @(
        'id_rsa'
        'id_ecdsa'
        'id_ecdsa_sk'
        'id_ed25519'
        'id_ed25519_sk'
    )

    if (-not $SshDir) {
        $SshDir = Join-Path $HOME '.ssh'
    }

    foreach ($keyName in $defaultKeys) {
        $keyPath = Join-Path $SshDir $keyName
        if (Test-Path $keyPath) {
            return $keyPath
        }
    }

    return $null
}
