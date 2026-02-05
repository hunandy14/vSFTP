function Write-Summary {
    <#
    .SYNOPSIS
        顯示結果摘要。
    .PARAMETER Passed
        通過的檔案數。
    .PARAMETER Failed
        失敗的檔案數。
    .PARAMETER Skipped
        是否跳過驗證。
    #>
    [CmdletBinding()]
    param(
        [int]$Passed = 0,
        [int]$Failed = 0,
        [switch]$Skipped
    )
    
    Write-Host ""
    Write-Host "───────────────────────────────────────────────────────────────" -ForegroundColor Cyan
    
    if ($Skipped) {
        Write-Host "  Transfer completed (verification skipped)" -ForegroundColor Green
    } else {
        $color = if ($Failed -eq 0) { 'Green' } else { 'Red' }
        Write-Host "  Summary: $Passed passed, $Failed failed" -ForegroundColor $color
    }
    
    Write-Host "───────────────────────────────────────────────────────────────" -ForegroundColor Cyan
}
