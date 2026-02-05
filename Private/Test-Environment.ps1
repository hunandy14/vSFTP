function Test-Environment {
    <#
    .SYNOPSIS
        驗證必要的環境變數是否已設定。
    .DESCRIPTION
        檢查 SFTP 連線所需的環境變數，回傳缺少的變數清單。
    .OUTPUTS
        缺少的環境變數名稱陣列。如果全部都有設定，回傳空陣列。
    #>
    [CmdletBinding()]
    param()
    
    $missing = @()
    
    if (-not $env:SFTP_HOST) { $missing += 'SFTP_HOST' }
    if (-not $env:SFTP_USER) { $missing += 'SFTP_USER' }
    if (-not $env:SFTP_KEYFILE) { $missing += 'SFTP_KEYFILE' }
    
    return $missing
}
