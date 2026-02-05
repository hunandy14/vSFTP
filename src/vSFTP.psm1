#Requires -Version 7.0
#Requires -Modules Posh-SSH

# 匯入私有函數
$PrivatePath = "$PSScriptRoot/Private"
if (Test-Path $PrivatePath) {
    foreach ($file in Get-ChildItem -Path "$PrivatePath/*.ps1" -File) {
        try {
            . $file.FullName
        } catch {
            throw "Failed to import $($file.FullName): $_"
        }
    }
}

# 匯入公開函數
$PublicPath = "$PSScriptRoot/Public"
if (Test-Path $PublicPath) {
    $Public = Get-ChildItem -Path "$PublicPath/*.ps1" -File
    foreach ($file in $Public) {
        try {
            . $file.FullName
        } catch {
            throw "Failed to import $($file.FullName): $_"
        }
    }
    # 匯出公開函數
    Export-ModuleMember -Function $Public.BaseName
}
