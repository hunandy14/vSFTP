function Write-Banner {
    <#
    .SYNOPSIS
        顯示 vSFTP 標題橫幅。
    #>
    [CmdletBinding()]
    param()
    
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  vSFTP - SFTP with Hash Verification" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""
}
