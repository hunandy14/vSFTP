# vSFTP 模組（測試用）
# 根據 VSFTP_VARIANT 環境變數載入 Full 或 Lite 版本

$variant = if ($env:VSFTP_VARIANT -eq 'Lite') { 'Lite' } else { 'Full' }

# 載入共用函數
Get-ChildItem -Path "$PSScriptRoot/Common/*.ps1" -File | ForEach-Object {
    . $_.FullName
}

# 載入版本專用函數
Get-ChildItem -Path "$PSScriptRoot/$variant/*.ps1" -File | ForEach-Object {
    . $_.FullName
}

# 匯出公開函數
Export-ModuleMember -Function Invoke-vSFTP
