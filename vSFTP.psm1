#Requires -Version 7.0
#Requires -Modules Posh-SSH

# 匯入私有函數
$Private = @(Get-ChildItem -Path "$PSScriptRoot/src/Private/*.ps1" -ErrorAction SilentlyContinue)
foreach ($file in $Private) {
    try {
        . $file.FullName
    } catch {
        Write-Error "Failed to import $($file.FullName): $_"
    }
}

# 匯入公開函數
$Public = @(Get-ChildItem -Path "$PSScriptRoot/src/Public/*.ps1" -ErrorAction SilentlyContinue)
foreach ($file in $Public) {
    try {
        . $file.FullName
    } catch {
        Write-Error "Failed to import $($file.FullName): $_"
    }
}

# 匯出公開函數
Export-ModuleMember -Function $Public.BaseName
